# SlideRemote: pendências da revisão

Documento para retomar o trabalho em outra sessão. Reúne o que três revisões independentes
(segurança, concorrência/correção e arquitetura/testes/UX) encontraram no código depois das
Fases 1 a 5 de segurança.

> **Leia antes de agir.** Os revisores só **leram** o código; ninguém rodou o app em aparelhos.
> Cada item traz a confiança: **confirmado** (o código prova) ou **hipótese** (depende do
> comportamento real do Multipeer/SwiftUI). Os números de linha eram válidos no commit
> `72186b3` e podem ter se movido.

---

## 1. Estado do projeto

**O que é:** o iPad mostra um PDF; o iPhone controla os slides via MultipeerConnectivity; o
Apple Watch avisa o iPhone de um giro de pulso (cada gesto = próximo slide).

**Já feito (tudo em `main`, 119 testes passando, targets iOS e watchOS compilando):**

| Fase | Entrega |
|---|---|
| Arquitetura | Protocolos de transporte e carregamento de PDF, ViewModels nos dois lados, `RemoteCommand`/`RemoteService` em `Model/` |
| 1 | iPad aprova cada convite num alerta; um iPhone por vez; iPhone escolhe o iPad numa lista (sem convite automático) |
| 2 | Código de 6 dígitos na tela do iPad, validado dentro da sessão cifrada; 3 erros travam; prazo de 60 s para autenticar; botão "Desconectar iPhone" |
| 3 | Limite de 10 comandos/s por sessão; o receiver só repassa mensagens do peer aprovado |
| 4 | Retomada sem digitar o código: credencial só em memória, prova por HMAC-SHA256 com desafio de uso único, rotação a cada autenticação |
| 5 | `os.Logger` no lugar de `print` (nomes `.private`), `.gitignore`, limite de 200 MB no PDF, textos de permissão em português |

**Decisões já tomadas (não reabrir sem motivo):**
- Nada vai para o Keychain; a credencial de reconexão fica só em memória.
- O alerta de aprovação do iPad continua mesmo na retomada; só o **código** deixa de ser pedido.
- O bundle ID continua `project.SlideRemote` (a troca só vale antes de publicar ou usar TestFlight).
- Reconexão silenciosa (sem alerta) foi recusada: exigiria o iPad aceitar convites sem aprovação.
- O branch `slide-remote-with-mac-future-feature` existe e nunca foi tocado.

**O que NUNCA foi testado:** o fluxo com Multipeer real entre um iPhone e um iPad. O Multipeer
não é confiável no simulador. Ver o roteiro na seção 7.

---

## 2. Mapa do código

```
SlideRemote/
  Model/        PairingCode, PairingSession, InvitationPolicy, RemoteMessage, RemoteCommand,
                HexToken, ResumeProof, CommandThrottle, Presentation, RemoteService, AppLog
  iPad/
    Domain/       CommandReceiving, PDFLoading
    Data/         MultipeerCommandReceiver, SecurityScopedPDFLoader
    Presentation/ PresentationViewModel, PresentationView, PDFKitView
  iPhone/
    RemoteCommandSending.swift   (protocolos RemoteCommandSending e MovementSource, DiscoveredPeer)
    Data/         MultipeerRemoteSender
    Presentation/ RemoteViewModel, RemoteView
SlideRemoteWatch/  WatchArmDetector, WatchConnectivityManager (compilado também no iOS), ContentView
SlideRemoteTests/  Model/, iPad/, iPhone/   (Swift Testing)
```

Constantes atuais: alerta de convite 25 s · convite do iPhone expira em 30 s · prazo para
autenticar 60 s · 3 tentativas de código · 10 comandos/s · PDF até 200 MB · cooldown do gesto no Watch 1 s.

---

## 3. Lote 1: robustez e travas (começar por aqui)

- [ ] **1.1 `MCPeerID` pode derrubar o app na abertura** (alta, confirmado pela documentação da Apple)
  - `MCPeerID(displayName:)` lança exceção se o nome tiver mais de 63 bytes em UTF-8 ou for vazio.
  - Onde: `MultipeerCommandReceiver.swift` (criação do `peerID`) e `MultipeerRemoteSender.swift` (idem).
  - Correção: truncar por bytes UTF-8 em fronteira de `Character`; se vazio, usar "iPad"/"iPhone".
    Pede um teste puro (nome longo, com acentos/emoji, vazio).

- [ ] **1.2 Três erros de código criam uma sessão nova em vez de travar** (média, confirmado)
  - `PresentationViewModel.handlePairing`, caso `.locked`: faz `disconnectPeer()` e depois
    `startNewSession()`. Mensagens `.pair` já enfileiradas caem na sessão nova (código novo, 3
    tentativas novas), contornando o "travado para sempre" de `PairingSession`.
  - O `startNewSession()` ali é desnecessário: um peer novo precisa de novo convite, que já cria a sessão.
  - Correção: no `.locked`, só desconectar e encerrar a sessão (o equivalente a `disconnectPhone()`).
  - **Atenção:** os testes `threeWrongCodesLockDisconnectAndRenewCode` e `oldCodeDoesNotWorkAfterLock`
    consagram o comportamento atual e precisam ser reescritos antes (TDD).

- [ ] **1.3 iPhone preso sem saída** (média, confirmado)
  - `.connecting`: `select` muda a fase antes de `connect(to:)`, que dá `return` em silêncio se o iPad
    sumiu da lista. Nenhum evento chega e só o botão Cancelar tira o usuário dali.
    O `DiscoveredPeer.id` é um `UUID()` novo a cada descoberta, então uma linha antiga pode apontar para um id morto.
  - `.verifying` ("Verificando código..." / "Retomando conexão..."): não há timeout nem botão Cancelar.
    Se o iPad ignorar a mensagem (throttle, sessão caída), a tela fica ali até o prazo de 60 s do iPad derrubar a conexão.
  - **Convite fantasma:** cancelar no iPhone chama `session.disconnect()`, que não cancela um convite em andamento.
    O alerta continua no iPad até 25 s; se o apresentador tocar "Permitir", nasce uma sessão, um código e um prazo
    de 60 s para um peer que não existe (e convites reais são recusados nesse período).
  - Correções: `connect(to:)` devolver `Bool` (ou emitir `isConnected = false`) e o VM voltar a `.searching` com aviso;
    timeout próprio e botão "Cancelar" em `.verifying`; usar `session.cancelConnectPeer(_:)` em `disconnect()` quando
    ainda não conectou; no iPad, ao chegar novo convite do mesmo `MCPeerID` com um pendente, substituir o handler antigo.

- [ ] **1.4 Código de pareamento visível para a plateia** (média/alta, confirmado)
  - `PresentationView`: o código aparece em 72 pt **por cima do slide** enquanto o iPhone não autentica, e de novo
    se o iPhone cair e reconectar. Com o iPad projetado, qualquer um vê.
  - Correções: mostrar só na tela anterior à apresentação, ou sob demanda ("Mostrar código"), ou esconder em ~10 s/ao toque;
    mostrar contagem regressiva do prazo; opcionalmente esconder se `UIScreen.main.isCaptured`.

- [ ] **1.5 Evento fora de ordem apaga o prazo do peer recém-aprovado** (baixa/média, hipótese)
  - Um `.notConnected` atrasado (de um peer antigo) chega enquanto o novo peer aprovado ainda conecta
    (`connectedPeers` vazio) → `onConnectionChange(false)` → `endSession()` zera sessão, código e **cancela o prazo**.
    O peer conecta depois sem sessão e sem prazo, ocupando a vaga até o apresentador desconectar manualmente.
  - Variante: `startNewSession()` após `.locked` roda sem novo prazo e sem peer.
  - Correções: só chamar `endSession` se não houver peer aprovado/ativo; ou não cancelar o prazo de um peer aprovado;
    ou reiniciar o prazo sempre que uma sessão nova começa.
  - Relacionado (hipótese): um `.notConnected` atrasado de um `disconnect()` próprio pode derrubar uma nova tentativa
    ao mesmo peer no iPhone (`update` em `MultipeerRemoteSender`).

---

## 4. Lote 2: ciclo de vida e DoS

- [ ] **2.1 Multipeer nunca é reiniciado** (média, código confirmado; comportamento em segundo plano é hipótese)
  - `receiver.start()` roda no `init` do VM e `stop()` nunca é chamado; o browser do iPhone nunca para.
    Nada observa `scenePhase`; `didNotStartAdvertisingPeer` só loga e `didNotStartBrowsingForPeers` nem existe.
  - Efeito: depois do segundo plano, o iPhone fica em "Procurando iPad..." para sempre. Se a permissão de **rede local**
    for negada, o erro é silencioso.
  - Correção: reiniciar anúncio/busca em `.active`; expor erro de anúncio/busca ao VM e mostrar dica
    (mesma rede, Bluetooth, permissão de Rede Local).

- [ ] **2.2 Tela do iPhone bloqueia durante a apresentação** (média, hipótese de produto)
  - Com o Watch controlando, o usuário não toca o iPhone; a tela bloqueia, o app suspende, o Multipeer cai.
  - Correção: `UIApplication.shared.isIdleTimerDisabled = true` enquanto `phase == .paired`.

- [ ] **2.3 Spam de convites** (média, confirmado o caminho)
  - Quem convida em loop faz o alerta aparecer por cima dos slides (25 s por vez); com um convite pendente, o do iPhone
    legítimo é recusado em silêncio. Recusar/expirar não impõe cooldown.
  - Correções: cooldown/backoff por `MCPeerID` após recusa ou timeout; teto de alertas por minuto; **janela de pareamento**
    aberta pelo apresentador (botão "Parear iPhone", por tempo limitado); parar de anunciar depois de autenticar.

- [ ] **2.4 Identidade do peer é só o `displayName`** (média; gravidade real depende de teste em aparelho)
  - É falsificável e o alerta só mostra o nome. No iOS 16+, `UIDevice.current.name` tende a devolver nome genérico
    ("iPhone"/"iPad") sem o entitlement de nome atribuído pelo usuário; não há `.entitlements` no repo.
    Nesse caso os aparelhos colidem e `credentials[name]` no iPhone pode associar a credencial do iPad X ao iPad Y
    (o Y responde `resumeRejected` e o `forgetCredential()` apaga a do X).
  - **Primeiro:** confirmar em aparelho o que `UIDevice.current.name` devolve.
  - Correções possíveis: UUID de instalação anunciado em `discoveryInfo` e usado como chave; texto do alerta mais claro
    ("só aceite se você acabou de tocar em conectar no seu iPhone"); mostrar algo além do nome na lista do iPhone.
    Lembrar que o `context` do convite **não é cifrado**.

- [ ] **2.5 Endurecimentos pequenos** (baixa)
  - Limitar a ~128 bytes por mensagem **antes** de parsear (`RemoteMessage.init?(data:)`) e conferir o peer antes de decodificar.
  - No máximo 1 a 2 retomadas por convite aprovado; depois, forçar o fluxo com código.
  - Expirar a credencial (1 a 2 h) e limpá-la quando o iPad vai para segundo plano.
  - `.locked` pode não chegar ao iPhone (`send` seguido de `disconnect()` imediato): o iPhone deve esquecer a credencial
    em **qualquer** queda durante `.verifying`. Hoje, se o `.notConnected` chegar antes do `.credential`, a credencial é ignorada
    e a retomada futura falha. Opção: atrasar o `disconnectPeer()` no iPad depois do `.locked`.
  - `SecurityScopedPDFLoader`: se `fileSize` vier `nil` (`try?`, ex.: arquivo do iCloud não baixado), o limite é pulado.
    Tratar como erro ou ler com teto; considerar baixar o limite para 50 MB.
  - `rejected:N` aceita `+3`/`-0` (inofensivo); um iPad falso pode manter o iPhone na tela de código (o usuário cancela).

---

## 5. Lote 3: arquitetura e testes (regras do CLAUDE.md global)

- [ ] **3.1 Testes de tempo frágeis:** `PresentationViewModelTests` usa `Task.sleep` de 300 a 500 ms contra prazos de
  30 a 150 ms. Injetar um `Clock` (clock manual de teste) e eliminar os sleeps. Os testes "não dispara depois" passam
  por acaso se o timer quebrar de outra forma.

- [ ] **3.2 Receiver e sender reais sem teste.** O `FakeCommandReceiver` reimplementa a política em vez de testá-la e é
  **mais permissivo que o real** (não marca "aprovado e ainda conectando" como peer ativo; aceitaria um segundo convite).
  O `FakeSender` não filtra por `targetPeer` e `connect()` nunca falha, por isso o item 1.3 não aparece nos testes.
  Proposta: extrair o roteamento (convite pendente, aprovado, ativo, filtro de mensagens) para um tipo puro (`PeerGate`)
  testável, deixando a casca do Multipeer fina.

- [ ] **3.3 Watch sem teste.** Extrair a decisão do giro (`rate.x < -4`, dominância >= 0,9) para um `WristTwistClassifier`
  puro e testar com valores medidos; testar o cooldown com relógio injetado. Documentar que a divisão por `rotation`
  só roda depois de `rate.x < -4` (nunca é zero).

- [ ] **3.4 Frameworks vazando para o domínio:**
  `import PDFKit` em `PDFLoading` (o VM guarda `PDFDocument`; ele só precisa do `pageCount`);
  `CryptoKit` em `ResumeProof` (usar um protocolo de assinatura com a implementação CryptoKit fora do Model);
  `Combine`/`AnyPublisher` em `RemoteCommandSending` (o `CommandReceiving` do iPad já usa closures; deixar os dois simétricos);
  `OSLog`/`Bundle` em `AppLog` dentro de `Model/`, e o VM do iPad chamando `AppLog` direto.
  `PDFLoadError` mistura erro de domínio com texto de UI em português.

- [ ] **3.5 Estrutura:** `Model/` guarda entidades, value objects, DTO de fio, política e logger. Proposta:
  `Domain/` (`Presentation`, `PairingCode`, `PairingSession`, `HexToken`, `CommandThrottle`, `InvitationPolicy`, `RemoteCommand`),
  `Data/Wire/` (`RemoteMessage`, `RemoteService`), `Infrastructure/` (`AppLog`). Espelhar nos testes
  (hoje `PresentationViewModelTests` está em `iPad/` e o código em `iPad/Presentation/`). O iPhone não tem `Domain/`.

- [ ] **3.6 `RemoteMessage` mistura direções.** Cada VM faz `switch` completo e ignora os casos "do outro lado"
  (`case ... break`). Dividir em `PhoneToPadMessage` e `PadToPhoneMessage` faz o compilador garantir a direção.

- [ ] **3.7 `PresentationViewModel` (~230 linhas)** acumula máquina de pareamento, ciclo de convite e timers, rate limit e PDF.
  Extrair um controlador de pareamento testável sem `Task.sleep`; o VM só publica estado.
  Do lado do iPhone, `PairingPhase` e as regras (retomar vs. pedir código) também são de domínio.

- [ ] **3.8 Watch compartilhado entre targets.** `WatchConnectivityManager` compila nos dois targets (via
  `membershipExceptions`) com papéis opostos, e `extension WatchConnectivityManager: MovementSource {}` fica no iPhone.
  Separar em um emissor (Watch) e um receptor (iPhone), com as chaves `"movement"`/`"wristTwist"` num tipo pequeno comum.
  `RemoteView` usa `WatchConnectivityManager.shared` direto; injetar. `MainActor.assumeIsolated` em
  `startListeningToWatch` só é seguro porque o manager faz `DispatchQueue.main.async`; tipar o closure como `@MainActor`.
  A conformidade com protocolo `@MainActor` vira erro em Swift 6.

- [ ] **3.9 Assimetria entre receiver e sender** (um `@MainActor` com `nonisolated` + `Task`, o outro com `DispatchQueue.main.async`);
  `MCPeerID`/`MCSession` criados de forma duplicada. Extrair uma fábrica comum. Os três handlers vazios do `MCSessionDelegate`
  se repetem nos dois lados.

---

## 6. Lote 4: UX, constantes e documentação

- [ ] **4.1 UX**
  - Sem háptico no iPhone ao enviar next/previous ou ao parear; o Watch vibra ao detectar, **antes** de saber se o gesto foi entregue
    (`guard isReachable` descarta em silêncio). Vibrar `.success` só ao enviar e `.failure` se não houver conexão.
  - Auto-enviar ao digitar 6 dígitos; "Confirmar" desabilitado até lá.
  - O iPhone não é avisado quando o iPad fecha a apresentação (continua `.paired` com comandos viram no-op) nem quando o iPad
    está sem PDF.
  - `fileImporter` ignora `.failure`; `loadError` só aparece na tela vazia.
  - Estados vazios sem dica (mesma rede, Bluetooth, permissão de Rede Local); `notice` vermelho sem ação "Tentar novamente".
  - Título do alerta fica vazio durante a animação de fechar (`pendingInvitation ?? ""`). Se um convite chega com o seletor de arquivos
    aberto, o alerta pode só aparecer depois e expirar (25 s) sem o apresentador ver.
  - Watch: UI mínima em inglês, sem estado "iPhone conectado/fora de alcance" e sem informar que o gesto só avança.
  - Possível bug visual (**a confirmar**): no modo escuro o ícone branco do `ArrowButton` pode ficar sobre um círculo claro.
  - Acessibilidade: fontes fixas (`.system(size: 72/32/20)`) não escalam com Dynamic Type; falta anúncio de VoiceOver quando o
    pareamento muda; label "Slide Anterior" deveria ser "Slide anterior".
  - Previews (`#Preview { PresentationView() }` e `RemoteView()`) sobem o Multipeer real. Criar a composição numa raiz
    (`SlideRemoteApp`) com injeção.

- [ ] **4.2 Constantes nomeadas:** reunir 25 s, 60 s, 30 s, 10/s e 3 tentativas num `PairingPolicy`. O convite do iPhone (30 s) devia
  derivar do prazo do iPad (25 s) mais uma margem (hoje 5 s, curta). Também `0.02` (50 Hz) no Watch e as medidas fixas da UI.

- [ ] **4.3 Comentários e documentação**
  - Apagar o bloco didático sobre Multipeer no topo de `MultipeerCommandReceiver.swift` e os comentários inline que só traduzem a API.
  - Corrigir o comentário desatualizado "Antes de autenticar, ou sem PDF..." em `PresentationViewModel` (o `guard` só olha a autenticação).
  - Remover comentários que repetem o nome (`currentPage`, `codeError`, `CommandReceiving`, "preview: sem ação").
  - **Passe de `docs:` em commit próprio** (regra do CLAUDE.md) para os invariantes que o nome não diz:
    `PairingCode` (por que só ASCII e 6 dígitos), `HexToken.generate` (CSPRNG), `ResumeProof.compute` (a chave é a string hex em UTF-8,
    não os bytes decodificados; as duas pontas precisam repetir), `CommandThrottle` (instante monotônico injetado, `max(…, 1)`),
    `PairingSession.submit` (idempotente depois de autenticado), e o porquê do tempo constante.

- [ ] **4.4 Limpeza e nomes:**
  `RemoteService.type = "number-sync"` e `NSBonjourServices` (`_number-sync._tcp`) são do protótipo antigo (trocar nos três lugares juntos);
  cabeçalhos do Watch ainda dizem "RotateWristWatch"; `RemoteCommand.data`/`init?(data:)` talvez só os testes usem (confirmar com grep);
  `HexToken.swift` tem funções livres e um `private extension` só para contornar colisão de nome; `PairingCode.matches` reimplementa o XOR
  em vez de usar `constantTimeEquals`; `CommandThrottle` poderia ter `reset()` em vez de o VM guardar `throttleTemplate`;
  `Presentation(pageCount: 0)` é possível (`init?` para `pageCount < 1`); UI do Watch em inglês e logs misturados PT/EN;
  `NSMotionUsageDescription` no target do iPhone provavelmente desnecessário (só o Watch usa CoreMotion);
  três commits antigos sem prefixo Conventional Commits (anteriores ao CLAUDE.md).

---

## 7. Roteiro de teste com aparelhos reais (ainda não feito)

Precisa de **um iPhone, um iPad e, de preferência, um segundo iPhone** como intruso.

1. Pareamento normal: alerta no iPad, código visível, digitar no iPhone, setas funcionam, o Watch avança o slide.
2. Segundo iPhone tentando entrar durante a apresentação: recusado **sem** alerta.
3. Código errado 3 vezes: o iPhone é desconectado e o iPad gera código novo (hoje cria uma sessão nova; ver 1.2).
4. Recusar o convite: o iPhone volta à lista com "O iPad recusou ou não respondeu".
5. Aprovar e **não** digitar o código: após 60 s o iPad desconecta e aceita outro convite.
6. "Desconectar iPhone" no meio da apresentação: o iPad volta a aceitar convites.
7. Queda de Wi-Fi, depois escolher o mesmo iPad e tocar "Permitir": deve retomar **sem** pedir o código.
8. "Desconectar iPhone" e reconectar: deve pedir o código de novo. Fechar e reabrir o app do iPad: também.
9. Conferir o que `UIDevice.current.name` devolve em cada aparelho (item 2.4) e se um nome longo derruba o app (item 1.1).
10. Conferir que o filtro por peer não descarta tudo: o iPad compara `MCPeerID` com `==` em `didReceive`. Se o pareamento nunca
    completar mesmo com o código certo, o primeiro suspeito é esse `guard` em `MultipeerCommandReceiver`.
11. Deixar o app em segundo plano e voltar (item 2.1); bloquear a tela do iPhone durante a apresentação (item 2.2);
    cancelar um convite pelo iPhone e ver se o alerta fica preso no iPad (item 1.3).

---

## 8. Limitações conhecidas que continuam

- **MITM por relay (média/alta, não corrigido):** a sessão Multipeer é cifrada mas **não autentica** o peer (`securityIdentity: nil`).
  Um iPad falso com o mesmo nome pode repassar o código e a retomada ao iPad real: o HMAC prova posse da credencial, mas não amarra a
  prova ao canal, e o iPhone aceita `.pairingResult(.accepted)` de qualquer peer. Fechar de verdade exige autenticação mútua
  (PAKE como SPAKE2/CPace, ou certificado auto-assinado com fingerprint fixado depois do primeiro pareamento). É trabalho grande;
  para uso em apresentações próximas, o plano é documentar o limite e tratar depois.
- Um peer autenticado malicioso ainda passa até 10 slides/s (risco interno).
- Não há reconexão silenciosa: o apresentador ainda toca "Permitir" e o iPhone ainda escolhe o iPad na lista.
- A credencial é por **nome** de iPad no iPhone (ver 2.4); o HMAC impede que isso vaze a credencial.

---

## 9. Como rodar e convenções

**Regras do usuário (`~/.claude/CLAUDE.md`):** Clean Architecture estrita, TDD (teste vermelho primeiro, commits `test:` → `feat:` →
`refactor:`), value objects que se auto-validam, domínio sem framework, comentários só para o porquê, `docs:` em commit separado,
nunca ler/logar `.env`/Keychain, não instalar dependências nem mexer na estrutura do projeto Xcode sem permissão.
Rodadas de teste limitadas: só a suíte relevante, em segundo plano, encerrando em 30 s.

**Testes** (o target `SlideRemoteTests` usa Swift Testing e já está no scheme `SlideRemote`). Troque o id pelo de um simulador iPhone
disponível (`xcrun simctl list devices available`) e suba-o antes (`xcrun simctl boot <id>; xcrun simctl bootstatus <id> -b`):

```bash
xcodebuild build-for-testing -scheme SlideRemote -destination 'platform=iOS Simulator,id=<ID>' -derivedDataPath /tmp/dd CODE_SIGNING_ALLOWED=NO
xcodebuild test-without-building -scheme SlideRemote -destination 'platform=iOS Simulator,id=<ID>' -derivedDataPath /tmp/dd -only-testing:SlideRemoteTests/<Suite>
xcodebuild build -scheme "SlideRemoteWatch Watch App" -destination 'generic/platform=watchOS Simulator' CODE_SIGNING_ALLOWED=NO
```

Armadilhas já encontradas:
- Um `RandomNumberGenerator` constante dentro de `Int.random(in:using:)` entra em loop infinito (rejeição). Não use isso em fakes.
- `#expect` não aceita chamar método `mutating` direto: guarde o resultado numa variável antes.
- A pasta do app usa *synchronized groups*: arquivos novos entram sozinhos, sem editar o `.pbxproj`.

---

## 10. Ordem sugerida para a próxima sessão

1. **Lote 1** em TDD (1.1 a 1.5), começando por 1.1 (crash) e 1.2 (reescrever os dois testes antes).
2. **Testar com aparelhos reais** (seção 7): vários itens dos lotes 2 e 3 dependem do comportamento real do Multipeer.
3. **Lote 2** (2.1 a 2.5), com a decisão sobre a janela de pareamento e a identidade do peer (2.4).
4. **Lote 3** (clock injetado, `PeerGate`, `WristTwistClassifier`, desacoplamento de frameworks).
5. **Lote 4** (UX, constantes, passe de `docs:`).
6. Decidir se o MITM por relay (seção 8) será tratado.
