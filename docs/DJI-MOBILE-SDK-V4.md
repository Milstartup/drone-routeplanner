# Koppeling met DJI Mobile SDK v4 (iOS) en de originele Mavic Mini

Onderzocht op **25 oktober 2026**, op basis van officiële documentatie van DJI en Apple. Elke bewering heeft een bronlabel:

- **[officieel]**: van DJI of Apple zelf.
- **[community]**: meldingen van ontwikkelaars of gebruikers. Nuttig, maar niet bevestigd door DJI.
- **[niet gevonden]**: niet in officiële bronnen terug te vinden. Moet getest worden.
- **[getest]**: zelf getest met de eigen app, de Mavic Mini en de iPhone 13 (zie [STAPPENPLAN.md](STAPPENPLAN.md), stap 2).

Alleen wat [getest] heet, is met een echte drone geprobeerd. API-namen staan precies zoals in de Objective-C-documentatie van DJI. Swift-namen staan er alleen bij als ze in DJI's eigen Swift-voorbeeldcode voorkomen.

## Samenvatting

1. **Het kan, maar alleen met de iPhone als "piloot".** SDK v4 voor iOS ondersteunt de Mavic Mini. De Mini kan echter **geen waypoint-missies aan boord** uitvoeren. De app moet de drone daarom tijdens de hele vlucht zelf sturen met *Virtual Stick*: 5 tot 25 stuurcommando's per seconde vanaf de iPhone.
2. **Het platform staat stil.**
   - De laatste iOS-SDK is 4.16.2, uitgebracht op 26 oktober 2022.
   - DJI kondigde in 2023 aan te stoppen met updates van de iOS-SDK.
   - DJI stopte op 1 april 2026 met service voor de Mavic Mini.
   - De nieuwe SDK v5 werkt alleen op Android en ondersteunt de Mavic Mini niet.
3. **Bouwen met de huidige Xcode lukt niet zonder ingrepen.** De App Store eist sinds 28 april 2026 Xcode 26 of nieuwer. Volgens ontwikkelaars bouwt de DJI-SDK met de iOS 26-SDK niet meer zonder een omweg [community].
4. **Publiceren in de App Store is waarschijnlijk onmogelijk.** DJI moet daarvoor een MFi-aanvraag indienen, en DJI neemt geen nieuwe MFi-aanvragen meer aan. Reken op een app voor eigen gebruik, die je via Xcode op je eigen iPhone zet.
5. **Advies:** begin met een kleine haalbaarheidstest. Bouw op een Mac een minimale app die registreert, verbinding maakt, de telemetrie toont en op de grond een foto maakt. Doe dat vóórdat je de volledige vlucht-app bouwt. Lukt die stap niet, kijk dan naar de alternatieven in hoofdstuk 7.

## 1. Status van SDK en drone

| Onderwerp | Bevinding | Bron |
|---|---|---|
| Mavic Mini ondersteund | Ja. Staat in de lijst "Supported Products" van de iOS-releasenotes 4.15 t/m 4.16.2, met firmware 01.00.0500. | [officieel] [Release notes iOS](https://developer.dji.com/document/2c6f3a26-412e-45d2-a312-eb82e72411e7) |
| Sinds welke versie | 4.13 (juli 2020): `DJIAircraftModelNameMavicMini` toegevoegd | [officieel] [Header-diff 4.12→4.13](https://github.com/dji-sdk/Mobile-SDK-iOS/blob/master/docs/SDK%20Headers%20Diff/4.12_4.13_diff.html) |
| Laatste iOS-versie | 4.16.2, 26 oktober 2022. Laatste commit in de repository: dezelfde dag. | [officieel] [Podspec](https://github.com/dji-sdk/Mobile-SDK-iOS/blob/master/DJI-SDK-iOS.podspec) |
| Ontwikkeling gestopt | Aankondiging van november 2023: geen nieuwe versies van de iOS-SDK, geen nieuwe MFi-aanvragen. Technische ondersteuning blijft. DJI raadt Android aan. | [officieel, achter login] [DJI-forum](https://sdk-forum.dji.net/hc/en-us/articles/25786229596057-Part-of-DJI-SDK-stops-updating-announcement); gelezen via [community] [DroneDJ](https://dronedj.com/2023/11/30/dji-ios-sdk-android-app/) |
| SDK v5 | Alleen Android. De productlijst (Mini 3, Mini 3 Pro, Mini 4 Pro, Mavic 3E/3M, M30, M300/M350, Matrice 4) noemt de Mavic Mini niet. | [officieel] [developer.dji.com/mobile-sdk](https://developer.dji.com/mobile-sdk/) |
| Service drone | Mavic Mini: productie gestopt oktober 2021, service gestopt 1 april 2026 | [officieel] [DJI-mededeling](https://support.dji.com/help/content?customId=en-us03400007185&spaceId=34&re=US&lang=en) |
| Android ter vergelijking | De Android-SDK v4 liep door tot 4.18 (24 oktober 2024) | [officieel] [Release notes Android](https://developer.dji.com/document/122b5969-d64d-4752-8452-400c41240aa5) |

## 2. Wat de Mavic Mini via de SDK wel en niet kan

| Functie | Mavic Mini | Bron |
|---|---|---|
| Waypoint-missie (aan boord) | **Nee** ("-" in DJI's producttabel) | [officieel] [Hardware Introduction](https://developer.dji.com/document/52b7f3b9-a773-47b3-b9e5-71c7a3190736) |
| Waypoint V2 | Nee: `waypointV2MissionOperator` is "Only Supported by Matrice 300 RTK" | [officieel] [DJIMissionControl](https://developer.dji.com/api-reference/ios-api/Components/Missions/DJIMissionControl.html) |
| Hotpoint, Follow Me, ActiveTrack, TapFly | Nee ("-") | [officieel] Hardware Introduction |
| Obstakeldetectie | Nee. Alleen een camera naar beneden voor positiebepaling (0,5–10 m). | [officieel] Hardware Introduction en [specs](https://www.dji.com/support/product/mavic-mini) |
| Virtual Stick | Geen uitzondering voor de Mini genoemd. De afstandsbediening moet in de **P-stand** staan om de SDK te gebruiken. | [officieel] Hardware Introduction |
| Camera: losse foto en interval | De drone kent losse foto en interval 2/3/5/7/10/15/20/30/60 s, alleen JPEG. Een Mini-specifieke SDK-regel voor interval is niet gevonden. | [officieel] specs; SDK-detail [niet gevonden] |
| Opslaglocatie kiezen | Nee: `setStorageLocation:withCompletion:` is "Not supported by Mavic Mini…" | [officieel] [DJICamera](https://developer.dji.com/api-reference/ios-api/Components/Camera/DJICamera.html) |
| Gimbal | Kantelbereik −90° tot 0° (uitgebreid tot +20°) | [officieel] specs |
| Live beeld | Bekend probleem: "When Mavic Mini starts to use the image transfer function, it will refresh slowly" | [officieel] Release notes 4.15 |
| Opstijgen zonder GPS | Toegevoegd in 4.16 | [officieel] Release notes |

## 3. Relevante API's

Alle namen hieronder staan in de officiële API-referentie van DJI voor iOS v4. Gebruik geen namen die hier niet staan zonder ze eerst in de headers van de SDK op te zoeken.

### Registratie en verbinding

Bron: [officieel] [DJISDKManager](https://developer.dji.com/api-reference/ios-api/Components/SDKManager/DJISDKManager.html)

- **App-sleutel:** `DJISDKAppKey` in Info.plist. De sleutel is gekoppeld aan de Bundle ID. Bij de eerste start controleert de app de sleutel via internet bij DJI.
- **Registreren:** `+registerAppWithDelegate:`, met delegate `-appRegisteredWithError:` en `-didUpdateDatabaseDownloadProgress:` (Fly Safe-database).
  - Swift-voorbeeld: `DJISDKManager.registerApp(with:)`.
- **Verbinden:** `+startConnectionToProduct` (na geslaagde registratie), `+stopConnectionToProduct` en `+product`.
  - Delegate: `-productConnected:`, `-productDisconnected`, `componentConnectedWithKey:andIndex:` en `componentDisconnectedWithKey:andIndex:`.
- **Achtergrond:** `+closeConnectionWhenEnteringBackground:` staat standaard op YES. De app moet dus op de voorgrond blijven tijdens de vlucht.
- **Testen zonder kabel aan de Mac:** `+enableBridgeModeWithBridgeAppIP:` met de DJI SDK Bridge-app. Daarmee kan je app in de iOS-simulator of op een ander toestel draaien.

### Telemetrie

Bron: [officieel] [DJIFlightControllerState](https://developer.dji.com/api-reference/ios-api/Components/FlightController/DJIFlightController_DJIFlightControllerCurrentState.html)

- **Delegate:** `-flightController:didUpdateState:` levert tot 10 keer per seconde de toestand.
- **Velden:**
  - Positie en hoogte: `aircraftLocation` en `altitude` (barometer, ten opzichte van de startplek).
  - Snelheid: `velocityX/Y/Z` (noord-oost-omlaag).
  - Status: `attitude`, `isFlying`, `areMotorsOn`, `flightMode`, `flightModeString`.
  - GPS: `satelliteCount` en `GPSSignalLevel`.
  - Thuispunt: `homeLocation`, `isHomeLocationSet` en `goHomeExecutionState`.
  - Wind: `windWarning`.

### Virtual Stick: de drone sturen vanaf de iPhone

Bron: [officieel] [DJIFlightController](https://developer.dji.com/api-reference/ios-api/Components/FlightController/DJIFlightController.html) en [Flight Controller-gids](https://developer.dji.com/document/0e5d22b9-efcf-4fe5-8cf4-80d410f2b690)

- **Aan en uit:** `-setVirtualStickModeEnabled:withCompletion:`, `-getVirtualStickModeEnabledWithCompletion:` en `-isVirtualStickControlModeAvailable`.
- **Sturen:** `-sendVirtualStickFlightControlData:withCompletion:` met `DJIVirtualStickFlightControlData` (`pitch`, `roll`, `yaw`, `verticalThrottle`).
- **Stuurstanden:**
  - Hoogte: `verticalControlMode` als `…Velocity` (±4 m/s) of `…Position` (0–500 m).
  - Horizontaal: `rollPitchControlMode` als `…Angle` (±30°) of `…Velocity` (±15 m/s).
  - Draaien: `yawControlMode` als `…Angle` of `…AngularVelocity`.
  - Assenstelsel: `rollPitchCoordinateSystem` als `…Ground` of `…Body`.
- **Verzendfrequentie:** "Virtual stick commands should be sent to the aircraft between 5 Hz and 25 Hz."
- **Als er geen commando's meer komen:** volgens DJI kan de drone de verbinding dan als verbroken zien en blijft hij op zijn plek hangen tot het volgende commando.
- **Bekende fouten** [officieel, FAQ en release notes]:
  - De yaw in de stand `Angle` verloopt. DJI raadt `DJIVirtualStickYawControlModeAngularVelocity` aan.
  - Na het wisselen van de coördinatenstand kan de drone het laatste oude commando nog uitvoeren (firmwarefout).
  - `startTakeoffWithCompletion:` kan een fout melden terwijl het opstijgen wel lukt.

### Camera en gimbal

Bron: [officieel] [DJICamera](https://developer.dji.com/api-reference/ios-api/Components/Camera/DJICamera.html) en [DJIGimbal](https://developer.dji.com/api-reference/ios-api/Components/Gimbal/DJIGimbal.html)

- **Stand kiezen:** `-setMode:withCompletion:`. Gebruik `-setFlatMode:withCompletion:` alleen als `isFlatCameraModeSupported` YES is; controleer dat in de app.
- **Foto's maken:** `-setShootPhotoMode:withCompletion:` met `DJICameraShootPhotoModeSingle` of `…Interval`, plus `-startShootPhotoWithCompletion:` en `-stopShootPhotoWithCompletion:`.
- **Interval instellen:** `-setPhotoTimeIntervalSettings:withCompletion:`. Voor JPEG is het minimum 2 s.
- **Terugmeldingen:** `camera:didUpdateSystemState:` en `camera:didGenerateNewMediaFile:`. Die laatste gebruik je om te tellen of elke foto echt gemaakt is.
- **Gimbal recht naar beneden:** `-rotateWithRotation:completion:` met `DJIGimbalRotation` (`+gimbalRotationWithPitchValue:rollValue:yawValue:time:mode:ignore:`) in `DJIGimbalRotationModeAbsoluteAngle`, pitch −90.

### Accu, terugkeer en landen

Bron: [officieel] [DJIBatteryState](https://developer.dji.com/api-reference/ios-api/Components/Battery/DJIBattery_BatteryState.html) en de DJIFlightController-pagina hierboven

- **Accu:** `-battery:didUpdateState:` levert `chargeRemainingInPercent`, `voltage` en `temperature`.
- **Accuwaarschuwingen:** `isLowerThanBatteryWarningThreshold`, `isLowerThanSeriousBatteryWarningThreshold` en `batteryThresholdBehavior`.
  - De lage drempel kan op de Mini **niet** worden ingesteld (`setLowBatteryWarningThreshold` wordt niet ondersteund).
  - De ernstig-lage drempel kan wel worden ingesteld (`setSeriousLowBatteryWarningThreshold`).
- **Terugkeerberekening:** `goHomeAssessment` (`DJIFlightControllerGoHomeAssessment`) geeft:
  - `remainingFlightTime` en `timeNeededToGoHome`;
  - `batteryPercentageNeededToGoHome` en `maxRadiusAircraftCanFlyAndGoHome`;
  - `smartRTHState` en `smartRTHCountdown`.
- **Slimme terugkeer:** `setSmartReturnToHomeEnabled:` en `confirmSmartReturnToHomeRequest:`. Bij de Mini keert de drone terug als de accu laag is.
- **Verbinding weg:** `setConnectionFailSafeBehavior:withCompletion:` met `…Hover`, `…Landing` of `…GoHome` wordt ondersteund op de Mavic Mini. Volgens de gids begint de drone na 3 seconden verbindingsverlies aan dit gedrag.
- **Naar huis en landen:** `startGoHomeWithCompletion:` en `cancelGoHomeWithCompletion:`, `setGoHomeHeightInMeters:withCompletion:` (20–500 m), en `startLandingWithCompletion:` en `confirmLandingWithCompletion:`.

### Afstandsbediening

Bron: [officieel] [DJIRemoteController](https://developer.dji.com/api-reference/ios-api/Components/RemoteController/DJIRemoteController.html)

- **Knoppen en sticks volgen:** `remoteController:didUpdateHardwareState:` levert `DJIRCHardwareState` (sticks, knoppen, `flightModeSwitch`).
  - Let op: `pauseButton` geldt volgens DJI alleen voor afstandsbedieningen van de Phantom 4.
- **Geen fysieke standschakelaar:** de afstandsbediening van de Mini heeft er geen. De stand wordt in software gezet met `setSoftSwitchJoyStickMode:` (S/P/T). Volgens DJI is dat "Only Supported by Mavic Mini, DJI Mini SE".

## 4. Compatibiliteit met de huidige iOS en Xcode (oktober 2026)

| Onderwerp | Bevinding | Bron |
|---|---|---|
| Huidige versies | Xcode 27.1 (15 oktober 2026), iOS 27.0.1. Xcode 27 draait alleen op Macs met een Apple-chip en macOS Tahoe 26.6 of nieuwer, en debugt op iOS 17 en nieuwer. | [officieel] [Apple releases](https://developer.apple.com/news/releases/) en [Xcode 27 release notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-27-release-notes) |
| App Store-eis | Sinds 28 april 2026 bouwen met Xcode 26 of nieuwer en de iOS 26-SDK | [officieel] [Upcoming requirements](https://developer.apple.com/news/upcoming-requirements/) |
| **Getest op 26 oktober 2026** | Gebouwd met Xcode 16.4 (iOS 18.5-SDK), op een iPhone 13 met **iOS 27.0.1**: de SDK start, de App Key wordt geaccepteerd, de verbinding via de Lightning-kabel werkt, de camera maakt een foto, en accu, GPS en firmware (pakket 01.00.0500, opgehaald bij DJI's server) worden uitgelezen. | [getest] [STAPPENPLAN.md](STAPPENPLAN.md), stap 2 |
| Bouwfout met de iOS 26-SDK | "'ALAssetsLibrary' is unavailable in iOS". De omweg is headers aanpassen en een eigen stub-framework toevoegen; de melder waarschuwt voor mogelijke crashes. | [community] [Issue #560](https://github.com/dji-sdk/Mobile-SDK-iOS/issues/560) |
| Installatie | Alleen via CocoaPods (`pod 'DJI-SDK-iOS', '~> 4.16.2'`, plus `DJIWidget`). Geen Swift Package Manager. CocoaPods trunk neemt vanaf 2 december 2026 geen nieuwe podspecs meer aan; bestaande blijven werken. | [officieel] [Podfile-voorbeeld](https://github.com/dji-sdk/Mobile-SDK-iOS/blob/master/Sample%20Code/SwiftSampleCode/Podfile) en [CocoaPods](https://blog.cocoapods.org/CocoaPods-Specs-Repo/) |
| Bitcode | Opgelost in 4.16.2 ("Remove bitcode on Xcode 14") | [officieel] Release notes |
| Simulator op een Apple-chip | Het framework is een oud "fat framework" zonder arm64-simulator. De simulator moet via Rosetta draaien, en Apple stopt Rosetta na macOS 27. | [officieel] Podspec en [macOS 26.4 notes](https://developer.apple.com/documentation/macos-release-notes/macos-26_4-release-notes) |
| Echte iPhone nodig | Ja. Apps kunnen in de simulator of op een Mac geen MFi-accessoires (de afstandsbediening) gebruiken. Alleen via de Bridge-app kan het zonder. | [officieel] [Apple External Accessory](https://developer.apple.com/documentation/externalaccessory) |
| Info.plist | `UISupportedExternalAccessoryProtocols` met `com.dji.video`, `com.dji.protocol` en `com.dji.common` (in het Swift-voorbeeld ook `com.dji.logiclink`). Volgens DJI's handleiding ook App Transport Security openzetten. | [officieel] [Info.plist van het voorbeeld](https://github.com/dji-sdk/Mobile-SDK-iOS/blob/master/Sample%20Code/SwiftSampleCode/DJISDKSwiftDemo/Info.plist) |
| App Store en MFi | Voor publicatie moet DJI een MFi-aanvraag indienen. DJI neemt sinds 2023 geen nieuwe aan. Voor builds op je eigen iPhone noemt DJI deze stap niet. | [officieel] [DJI Deploy](https://developer.dji.com/document/ce784c1f-eaba-4be7-a1a5-b9cf6ce9105c) |
| App-sleutel aanmaken | De registratiepagina's bestaan nog. Of DJI nog nieuwe sleutels uitgeeft en hoe lang de controleserver blijft draaien, is niet bevestigd. | [officieel] / [niet gevonden] |
| iPhone met USB-C | Gebruikers melden dat een iPhone 15 (USB-C) geen verbinding maakt met de afstandsbediening van de Mini, terwijl een iPhone 13 of 14 wel werkt (in DJI Fly). | [community] [MavicPilots](https://mavicpilots.com/threads/mavic-mini-iphone-15-pro-not-working.142737/) |
| Firmware | De iOS-releasenotes noemen firmware 01.00.0500. Of nieuwere firmware (01.00.0600) werkt met iOS, is niet bevestigd. | [officieel] / [niet gevonden] |

## 5. Wat je nodig hebt voor de iPhone-app

- **Een Mac met Xcode.** Op Windows kun je geen iOS-app bouwen of op een iPhone zetten.
  - Met een Apple-chip: de nieuwste Xcode.
  - Met een **Intel-chip**: Xcode 27 werkt niet, maar Xcode 26.x of 16.x wel, afhankelijk van de macOS-versie (tabel in [STAPPENPLAN.md](STAPPENPLAN.md), stap 0).
  - Voor eigen gebruik is dat genoeg. Met Xcode 16 (iOS 18-SDK) speelt de bouwfout met de iOS 26-SDK niet.
  - De simulator van de DJI-SDK (alleen voor Intel gebouwd) draait op een Intel-Mac zonder Rosetta.
- **Een Apple-ontwikkelaarsaccount.**
  - Met een gratis account kun je op je eigen iPhone installeren, maar de app verloopt dan na korte tijd.
  - Met een betaald account (Apple Developer Program) gaat dat langer mee.
- **Een DJI-ontwikkelaarsaccount** met een App Key voor de Bundle ID van de app.
- **Een iPhone met iOS 17 of nieuwer**, een passende kabel naar de afstandsbediening, en de Mavic Mini met zijn afstandsbediening. Test eerst of de iPhone in DJI Fly verbinding maakt; bij USB-C-iPhones zijn er problemen gemeld.
- **CocoaPods** om de DJI-SDK binnen te halen.

## 6. Ontwerp van de latere iPhone-app

### 6.1 Scheiding

```
Planner (deze browser-app)   ──  .routeplan.json  ──►   iPhone-app
  tekent, rekent, controleert                           leest in, controleert opnieuw,
  geen dronecode                                        vliegt via de DJI-SDK
```

- De iPhone-app gebruikt de planner niet rechtstreeks. Hij leest alleen het bestand (zie [ROUTEBESTAND.md](ROUTEBESTAND.md)).
- Binnen de app houd je drie lagen gescheiden:
  - **Route en voortgang:** puur Swift en testbaar zonder drone.
  - **Veiligheidsregels:** een toestandsmachine, ook testbaar zonder drone.
  - **DJI-adapter:** de enige plek die DJI-API's aanroept.
- Zo kun je bijna alles testen met een nep-drone, en bevat de DJI-adapter zo weinig mogelijk logica.

### 6.2 Hoe de route gevlogen wordt

- Omdat de Mini geen waypoint-missies kent, stuurt de app zelf.
- **Stuurlus van ongeveer 10 Hz.** De app stuurt `sendVirtualStickFlightControlData` binnen de grenzen van 5–25 Hz die DJI noemt.
  - Horizontaal: snelheid in het grondassenstelsel, gericht naar het volgende routepunt, met afremmen vlak voor het punt.
  - Hoogte: in de positiestand op de geplande hoogte.
  - Draaien: met de hoeksnelheidsstand (vanwege de bekende fout in de hoekstand).
- **Welke kant op is "pitch"?** DJI's gids en DJI's voorbeeldcode lijken elkaar hierover tegen te spreken. **Test dit eerst in de simulator van de SDK** voordat je buiten vliegt.
  - De header `DJIFlightControllerBaseTypes.h` zegt: in het grondassenstelsel met snelheidsstand is pitch positief = **oost** en roll positief = **noord** [officieel].
  - De app vertrouwt daar niet blind op. Elke vlucht begint met een **richtingtest** die het meet, en de app stuurt op wat hij meet (`AxisMapping.swift`).
- **Foto's:** er zijn twee mogelijkheden.
  1. **Een losse foto per geplande fotopositie** (`DJICameraShootPhotoModeSingle`, `startShootPhoto`). De app neemt een foto zodra de drone binnen een paar meter van de volgende fotopositie is. Dat werkt het netst met wind, maar het interval mag niet korter zijn dan de camera aankan (aanname: 2 s, zoals de kortste intervalstand).
  2. **De intervalstand van de camera** (`setPhotoTimeIntervalSettings`, minimaal 2 s) aan het begin van elke vliegbaan aanzetten en aan het eind uitzetten. Dat is eenvoudiger, maar de afstand tussen foto's hangt dan af van de werkelijke snelheid.
- **Voortgang bijhouden:** de app onthoudt welke fotopositie het laatst gelukt is (via `camera:didGenerateNewMediaFile:`). Zo kan een onderbroken vlucht later precies daar verder.

### 6.3 Toestanden

| Toestand | Wat er gebeurt | Naar |
|---|---|---|
| Niet verbonden | Registreren, verbinding zoeken | Verbonden |
| Verbonden | Voorcontroles: accu, GPS (`GPSSignalLevel`, `satelliteCount`), thuispunt gezet, wind, route opnieuw gevalideerd, failsafe ingesteld | Klaar (alleen als alles in orde is) |
| Klaar | Piloot bevestigt de route op het scherm | Opstijgen |
| Opstijgen | Opstijgen en klimmen naar de vlieghoogte | Naar start, of Pauze/Terugkeer bij problemen |
| Naar start | Vliegen naar het eerste routepunt, nog geen foto's | Route vliegen |
| Route vliegen | Stuurlus en foto's | Pauze, Overname, Terugkeer, Klaar met route |
| Pauze | Stilhangen op de plek (nulsnelheid), voortgang bewaard | Route vliegen (hervatten), Terugkeer, Overname |
| Overname | Virtual Stick uit, de piloot vliegt zelf | Terugkeer of landen door de piloot; nooit automatisch hervatten |
| Terugkeer | `startGoHome` | Landen |
| Klaar met route | Terug naar huis en landen | Einde |

### 6.4 Verbinding

- **Volgorde:** registreren (eenmalig online), dan `startConnectionToProduct`, dan wachten op `productConnected`. Controleer dat de vluchtcomputer, camera, gimbal en accu er zijn.
- **Voorgrond:** de SDK verbreekt standaard de verbinding als de app naar de achtergrond gaat. Houd de app op de voorgrond en zet de automatische schermvergrendeling uit tijdens de vlucht.
- **Status op het scherm:** laat altijd twee verbindingen apart zien:
  - **iPhone ↔ afstandsbediening** (de kabel; `productDisconnected`);
  - **afstandsbediening ↔ drone** (wifi; componenten die wegvallen).

### 6.5 Handmatige overname

- Een grote knop **Overnemen** zet Virtual Stick uit (`setVirtualStickModeEnabled:NO`). Daarna vliegt de piloot zelf met de sticks.
- **Sticks bewegen tijdens de route:** of dat bij de Mini vanzelf Virtual Stick afbreekt, is **niet bevestigd**. Daarom bewaakt de app zelf de sticks via `remoteController:didUpdateHardwareState:`. Komt een stick duidelijk uit het midden, dan stopt de app direct met sturen en schakelt Virtual Stick uit.
- De Mini heeft **geen fysieke standschakelaar** en `pauseButton` geldt niet voor deze afstandsbediening. Volgens de gebruikershandleiding remt de drone af na één druk op de pauze/RTH-knop [community-kopie van de handleiding]. **Test dit op een veilige plek** voordat je erop vertrouwt.
- Na een overname gaat de app **nooit automatisch** verder. Hervatten vraagt altijd een bevestiging van de piloot.

### 6.6 Verbindingsverlies

- **Vooraf instellen:** stel vóór het opstijgen `setConnectionFailSafeBehavior` in op `…GoHome` en `setGoHomeHeightInMeters` boven de hoogste obstakels rond het veld (minimaal 20 m). Volgens DJI begint het failsafe-gedrag na 3 seconden zonder verbinding.
- **Als de app hapert:** stopt de stuurlus (app hangt, kabel los), dan blijft de drone volgens DJI stilhangen tot er weer commando's komen. De app moet dus bij elke onderbreking van de lus naar **Pauze** gaan, en mag niet "inhalen" met oude commando's.
- **Na herstel:** hervat nooit vanzelf. Toon de laatste voortgang en laat de piloot kiezen: hervatten, terugkeren of overnemen.
- **Buiten bereik:** de route kan niet verder buiten het bereik van de verbinding [community]. Houd de route binnen zicht. De planner waarschuwt al als het verste punt verder dan 500 m van het startpunt ligt.

### 6.7 Lage accu

- **Bewaken tijdens de vlucht:**
  - `chargeRemainingInPercent`;
  - `goHomeAssessment.batteryPercentageNeededToGoHome`;
  - `isLowerThanSeriousBatteryWarningThreshold`;
  - `smartRTHState` en `smartRTHCountdown`.
- **Eigen regel in de app:** de app breekt de route af zodra de accu onder (nodig om terug te keren + een vaste marge, bijvoorbeeld 10 procentpunt) komt. De voortgang wordt bewaard en de drone keert terug. Zo blijft de app vóór op de terugkeer die de drone zelf start.
- **Drempels van de Mini:**
  - De lage accudrempel van de Mini kun je niet instellen.
  - De ernstig-lage drempel kun je wel instellen; zet die bewust.
- **Slimme terugkeer:** start de drone zelf een terugkeer, dan volgt de app die. De app vecht daar nooit tegen met Virtual Stick-commando's.
- **Plannen per accu:** de planner waarschuwt al als een vlucht langer duurt dan de bruikbare accutijd. Verdeel grote velden over meerdere vluchten.

### 6.8 Route onderbreken en hervatten

- **Pauze:** stuur nulsnelheid; de drone hangt stil. De voortgang (laatste gelukte fotopositie, huidige baan) wordt bewaard.
- **Hervatten:** vlieg rechtstreeks naar het punt waar de vlucht stopte, op vlieghoogte, en ga verder vanaf de eerstvolgende fotopositie.
- **Afbreken:** stuur `startGoHome` en bewaar de voortgang. De volgende vlucht (nieuwe accu) kan dan verder vanaf die fotopositie.

### 6.9 Overige veiligheid

- **Geen obstakeldetectie en weinig windmarge:** de Mini ziet geen obstakels en kan wind tot 8 m/s aan. Kies een veilige hoogte en vlieg niet bij harde wind.
- **Fly Safe-database:** de SDK downloadt de Fly Safe-database (`didUpdateDatabaseDownloadProgress:`). Wacht tot die klaar is.
- **Regels:** controleer altijd de actuele regels voor drones in Nederland en de EU, zoals registratie als exploitant, no-fly-zones en maximale hoogte.

## 7. Risico's en alternatieven

**Grootste risico's**

1. Er zijn geen missies aan boord. Een haperende iPhone of kabel stopt de route meteen.
2. De SDK wordt niet meer bijgewerkt en de drone krijgt geen DJI-service meer.
3. De SDK bouwt niet zonder omweg met de verplichte Xcode-versie, en Rosetta verdwijnt.
4. Publicatie in de App Store is waarschijnlijk niet mogelijk; je bent aangewezen op eigen builds.
5. Je bent afhankelijk van DJI's servers voor de App Key.
6. Het overnemen door de piloot is voor de Mini slecht gedocumenteerd.

**Alternatieven om te onderzoeken** (niet uitgewerkt):

- **Android met SDK v4.** DJI raadde in 2023 Android aan en die SDK kreeg langer updates (tot 4.18). Dezelfde beperking blijft: geen missies aan boord van de Mini.
- **Een nieuwer DJI-model dat SDK v5 ondersteunt** (alleen Android). Controleer per model in de officiële MSDK v5-documentatie welke missiefuncties beschikbaar zijn.
- **Bestaande apps die de Mavic Mini al via Virtual Stick laten vliegen**, zoals Litchi [community]. Onderzoek eerst of zo'n app met een geëxporteerde route uit de planner volstaat. De planner zou dan alleen een export naar dat formaat nodig hebben.

## Bronnen

- **DJI iOS-releasenotes:** <https://developer.dji.com/document/2c6f3a26-412e-45d2-a312-eb82e72411e7>
- **DJI Hardware Introduction (producttabel):** <https://developer.dji.com/document/52b7f3b9-a773-47b3-b9e5-71c7a3190736>
- **DJI API-referentie iOS:** <https://developer.dji.com/api-reference/ios-api/index.html>
- **DJI Flight Controller-gids:** <https://developer.dji.com/document/0e5d22b9-efcf-4fe5-8cf4-80d410f2b690>
- **DJI Mobile SDK iOS-repository:** <https://github.com/dji-sdk/Mobile-SDK-iOS>
- **DJI Mobile SDK v5:** <https://developer.dji.com/mobile-sdk/>
- **Mavic Mini-specificaties:** <https://www.dji.com/support/product/mavic-mini>
- **Einde service oude producten:** <https://support.dji.com/help/content?customId=en-us03400007185&spaceId=34&re=US&lang=en>
- **Apple:**
  - Releases: <https://developer.apple.com/news/releases/>
  - Upcoming requirements: <https://developer.apple.com/news/upcoming-requirements/>
  - External Accessory: <https://developer.apple.com/documentation/externalaccessory>
- **Community:**
  - GitHub-issues #560 en andere: <https://github.com/dji-sdk/Mobile-SDK-iOS/issues>
  - DroneDJ, november 2023
  - Dronelink-forum: <https://support.dronelink.com/hc/en-us/community/posts/360048862474>
  - Litchi-help: <https://flylitchi.com/help>
