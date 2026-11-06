//
//  MultipeerCommandReceiver.swift
//  SlideRemote
//
//  Runs on the iPad: advertises the service via MultipeerConnectivity and accepts the iPhone.
//

import MultipeerConnectivity // local peer-to-peer communication, no server or internet
/*
 A framework for direct communication between nearby devices, with no server and no backend.
 It works across iPhone, iPad and Mac.

 It picks the available transport on its own:
 - Wi-Fi on the same network (infrastructure)
 - peer-to-peer Wi-Fi (AWDL, similar to AirDrop), no router needed
 - Bluetooth

 It decides and switches between them depending on availability.
 */

final class MultipeerCommandReceiver: NSObject, CommandReceiving {
    var onMessage: (@MainActor (RemoteMessage) -> Void)?
    var onConnectionChange: (@MainActor (Bool) -> Void)?
    var onInvitation: (@MainActor (String) -> Void)?

    private let serviceType = RemoteService.type
    private let peerID = MCPeerID(displayName: UIDevice.current.name) // the iPad's identity on the network (set to the device name)
    private let mcSession: MCSession  // communication session
    private let mcAdvertiser: MCNearbyServiceAdvertiser // service advertiser

    // Invitation state: only read and written on the main thread.
    private var pendingInvitation: (peer: MCPeerID, handler: (Bool, MCSession?) -> Void)?
    private var approvedPeer: MCPeerID? // approved, but still connecting
    private var activePeer: MCPeerID? // the only peer whose messages are forwarded

    override init() {
        mcSession = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required) // encrypted traffic
        mcAdvertiser = MCNearbyServiceAdvertiser(peer: peerID, discoveryInfo: nil, serviceType: serviceType) // the iPhone looks for exactly this one identificador
        super.init()
        mcSession.delegate = self
        mcAdvertiser.delegate = self
    }

    func start() {
        mcAdvertiser.startAdvertisingPeer()
        AppLog.connectivity.info("Advertising service \(self.serviceType, privacy: .public) as \(self.peerID.displayName, privacy: .private)")
    }

    func stop() {
        mcAdvertiser.stopAdvertisingPeer()
        mcSession.disconnect()
        DispatchQueue.main.async {
            self.pendingInvitation?.handler(false, nil)
            self.pendingInvitation = nil
            self.approvedPeer = nil
            self.activePeer = nil
        }
    }

    func respondToInvitation(accept: Bool) {
        let respond = { [self] in
            guard let pending = pendingInvitation else { return }
            pendingInvitation = nil
            if accept {
                approvedPeer = pending.peer
                activePeer = pending.peer
                pending.handler(true, mcSession)
            } else {
                pending.handler(false, nil)
            }
        }
        if Thread.isMainThread { respond() } else { DispatchQueue.main.async(execute: respond) }
    }

    func send(_ message: RemoteMessage) {
        let peers = mcSession.connectedPeers
        guard !peers.isEmpty else { return }
        do {
            try mcSession.send(message.data, toPeers: peers, with: .reliable)
        } catch {
            AppLog.connectivity.error("Error sending message: \(error.localizedDescription, privacy: .public)")
        }
    }

    func disconnectPeer() {
        mcSession.disconnect()
        // Also releases a peer that was approved but never completed the connection; otherwise the slot would stay stuck.
        DispatchQueue.main.async {
            self.approvedPeer = nil
            self.activePeer = nil
        }
    }
}

// MARK: - MCNearbyServiceAdvertiserDelegate

extension MultipeerCommandReceiver: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        AppLog.connectivity.info("Invitation received from \(peerID.displayName, privacy: .private)")
        DispatchQueue.main.async {
            let hasActivePeer = self.pendingInvitation != nil
                || self.approvedPeer != nil
                || !self.mcSession.connectedPeers.isEmpty
            switch InvitationPolicy.decide(hasActivePeer: hasActivePeer) {
            case .reject:
                invitationHandler(false, nil)
            case .askUser:
                self.pendingInvitation = (peerID, invitationHandler)
                self.onInvitation?(peerID.displayName)
            }
        }
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        AppLog.connectivity.error("Error advertising: \(error.localizedDescription, privacy: .public)")
    }
}

// MARK: - MCSessionDelegate

extension MultipeerCommandReceiver: MCSessionDelegate {
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        // Content is never logged: it may be the pairing code.
        guard let message = RemoteMessage(data: data) else { return }

        DispatchQueue.main.async {
            // Even with a single peer at a time, messages from any other peer in the session are discarded.
            guard peerID == self.activePeer else { return }
            self.onMessage?(message)
        }
    }

    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        AppLog.connectivity.info("Connection state with \(peerID.displayName, privacy: .private): \(state.rawValue, privacy: .public)")
        DispatchQueue.main.async {
            // "Connecting" is not a drop yet: notifying now would erase the freshly created code.
            guard state != .connecting else { return }
            if self.approvedPeer == peerID { self.approvedPeer = nil }
            if state == .notConnected, self.activePeer == peerID { self.activePeer = nil }
            self.onConnectionChange?(!session.connectedPeers.isEmpty)
        }
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}
