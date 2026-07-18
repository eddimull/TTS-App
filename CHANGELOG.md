# Changelog

## [1.18.0](https://github.com/eddimull/TTS-App/compare/v1.13.0...v1.18.0) (2026-07-18)


### Bug Fixes

* **auth:** migrate keychain items across the first_unlock accessibility switch ([b076849](https://github.com/eddimull/TTS-App/commit/b076849ae3709591d5b88b6c9d4ba57e79af12b8))
* **auth:** migrate keychain items across the first_unlock accessibility switch ([d39473f](https://github.com/eddimull/TTS-App/commit/d39473fac6a726e20cb471bf1291b4f14f761c8a))
* **events:** route lightbox token read through SecureStorage ([397f2ab](https://github.com/eddimull/TTS-App/commit/397f2abb06c0b8656a167d32c240b1b625e8e000))
* **push:** bundle GoogleService-Info.plist on iOS + de-silence registration ([c27c5b0](https://github.com/eddimull/TTS-App/commit/c27c5b03b77bca7316fac8f8a8442b388630ea89))
* **push:** bundle GoogleService-Info.plist on iOS; surface registration failures ([f6fc347](https://github.com/eddimull/TTS-App/commit/f6fc347e523f7a907afdad1dad839a278d66a11a))
* **push:** explicitly register for remote notifications at launch ([5841d5c](https://github.com/eddimull/TTS-App/commit/5841d5c188e9b2658825f418f316260219b02eaf))
* **push:** explicitly register for remote notifications at launch (UIScene) ([e9e90ac](https://github.com/eddimull/TTS-App/commit/e9e90ac31db4efcbecfac3d6948bbb0d162a2b6f))
* **push:** forward APNs token to Firebase under UIScene lifecycle ([5bcfe06](https://github.com/eddimull/TTS-App/commit/5bcfe06cd4abe5f28adea47bcf3b475ad47654ad))
* **push:** forward APNs token to Firebase under UIScene lifecycle ([89002d4](https://github.com/eddimull/TTS-App/commit/89002d45d9cf2eb4985d68d34ad65e898b3cb16d))
* **push:** guard APNs token forwarding against pre-Firebase delivery ([38d62d7](https://github.com/eddimull/TTS-App/commit/38d62d71141e8d55d801514e5c37c17a5ee8bd2b))


### Miscellaneous Chores

* resync release-please past manually bumped versions ([a866b2f](https://github.com/eddimull/TTS-App/commit/a866b2fdd56477aa1cd337cdcd3aac5050b62345))

## [1.13.0](https://github.com/eddimull/TTS-App/compare/v1.12.0...v1.13.0) (2026-07-17)


### Features

* **bookings:** pinned comment bar on booking detail ([84fa3d2](https://github.com/eddimull/TTS-App/commit/84fa3d27f253e7dfcbf6839268516adf82611b24))
* cancelled rehearsal visibility on shared surfaces ([c6c2a3b](https://github.com/eddimull/TTS-App/commit/c6c2a3b0bbdabf5980e7d96a06764493332d22b4))
* **chat:** pinned CommentBar widget for detail screens ([fb4e991](https://github.com/eddimull/TTS-App/commit/fb4e991be93e38f8ad1d38781d99e7688376667e))
* **dashboard:** cancelled styling on event cards ([2a63555](https://github.com/eddimull/TTS-App/commit/2a635559710c4b5e667ba8ed1b7587e9922f62ed))
* **dashboard:** red faded marker for cancelled rehearsals ([8f4c1f9](https://github.com/eddimull/TTS-App/commit/8f4c1f930609ef152047a15c0d6cc98af65e322c))
* **dashboard:** unread-comment badge on event cards ([b509385](https://github.com/eddimull/TTS-App/commit/b5093858fe4cbe20afe53fa7889f51e90f9c885e))
* **events:** parse is_cancelled into EventSummary ([f634b4f](https://github.com/eddimull/TTS-App/commit/f634b4f043c0b8dfbf9d59ce6c375b75de9af41e))
* **events:** pinned comment bar on event detail ([bd0f786](https://github.com/eddimull/TTS-App/commit/bd0f78611d3e983362b132cc54390db4d1219e21))
* **events:** unreadCommentCount on EventSummary ([0a59639](https://github.com/eddimull/TTS-App/commit/0a59639c0df586a138f65a616c8fd0ebca2e894e))
* questionnaires on mobile — Phase 1 (templates CRUD + builder) ([ebd46e3](https://github.com/eddimull/TTS-App/commit/ebd46e3aec5f1082fde7ce55e8df44ddcdfea368))
* questionnaires on mobile — Phase 2 (sending, logs, booking integration, realtime) ([636a32a](https://github.com/eddimull/TTS-App/commit/636a32a89f97082aa4d8f19988eef92326eeca66))
* questionnaires on mobile — Phase 3 (apply-to-event + submission push) ([87c5542](https://github.com/eddimull/TTS-App/commit/87c5542da61711055c543e8a5d385fe9f1b285ae))
* **questionnaires:** apply-to-event actions on responses screen ([8ed3592](https://github.com/eddimull/TTS-App/commit/8ed359262560dc2d92f50c6792baf12d0db7dfec))
* **questionnaires:** booking detail questionnaires section ([ba779b3](https://github.com/eddimull/TTS-App/commit/ba779b3867d32c2d5e7021068643ce6b49774ea0))
* **questionnaires:** builder screen with reorder + dirty-tracked save ([f654e98](https://github.com/eddimull/TTS-App/commit/f654e9815061d1fdbf537e3c0d0277b96dc533e8))
* **questionnaires:** detail screen with sent log, filters + instance actions ([041965d](https://github.com/eddimull/TTS-App/commit/041965d96e3049b09498fe30e7fee5aa5289f3dc))
* **questionnaires:** editor state provider with bulk-save contract ([2552cf7](https://github.com/eddimull/TTS-App/commit/2552cf751578239d933f426c551e08f77943f42c))
* **questionnaires:** instance repository + providers ([57172c2](https://github.com/eddimull/TTS-App/commit/57172c2a78270373f383498f01e3b126225a183d))
* **questionnaires:** instance responses screen ([bbefe39](https://github.com/eddimull/TTS-App/commit/bbefe39dca552d50c678cd70fbfba6c09bb78c8c))
* **questionnaires:** instance wire models + endpoints ([127b8af](https://github.com/eddimull/TTS-App/commit/127b8afca0d836b35ed9db0a229ad71653666f09))
* **questionnaires:** interactive preview with live visibility ([f95bc1a](https://github.com/eddimull/TTS-App/commit/f95bc1a8a434a342efa9d065c8b7d1981d6d86bd))
* **questionnaires:** menu entry, routes, list screen + create sheet ([1a16986](https://github.com/eddimull/TTS-App/commit/1a16986ecfdf57ca80d036056fd928c4a04b2adf))
* **questionnaires:** per-field editor (settings, mapping, visibility rules) ([b9a5583](https://github.com/eddimull/TTS-App/commit/b9a55833639837bb9ac1b3bf100059149b773a32))
* **questionnaires:** questionnaire_submitted push type with deep link ([b4bb795](https://github.com/eddimull/TTS-App/commit/b4bb7958bf3bd2647bbbe64afab39de3bdf830c6))
* **questionnaires:** realtime invalidation for questionnaire models ([8c7544e](https://github.com/eddimull/TTS-App/commit/8c7544efe35053b184e1965ae2c336e4e1dd5e5d))
* **questionnaires:** repository + list/detail/catalog providers ([bdd207d](https://github.com/eddimull/TTS-App/commit/bdd207dadc75645413cfcc4e37cfec7d3954c2a8))
* **questionnaires:** response metadata, mapping labels + apply repository calls ([97095c2](https://github.com/eddimull/TTS-App/commit/97095c2cdb52e053c40d7c77d57bc95168d81f42))
* **questionnaires:** send sheets for questionnaire and booking flows ([5a97f27](https://github.com/eddimull/TTS-App/commit/5a97f27559b3e3343e88ba13bf7394fd85147765))
* **questionnaires:** visibility evaluator port ([6bb8a30](https://github.com/eddimull/TTS-App/commit/6bb8a30dee469a0ce6783da98be99e67ec26cdd4))
* **questionnaires:** wire models + API endpoints ([9d54b35](https://github.com/eddimull/TTS-App/commit/9d54b354fc62a7f4172d715b6b169abcb8b97821))
* **realtime:** refresh dashboard badges on message signals ([438945c](https://github.com/eddimull/TTS-App/commit/438945c9347d5b21e9e031be1f52a7e03942f97c))
* **rehearsals:** pinned comment bar on rehearsal detail ([699164f](https://github.com/eddimull/TTS-App/commit/699164ff668e109a382e0f3707afe77c7260804f))


### Bug Fixes

* address Copilot review — dedupe unreachable error handler, re-indent banner ([ec66af6](https://github.com/eddimull/TTS-App/commit/ec66af68c55d40df6661ec3e627355dfe71a2bf8))
* **chat:** settle in-flight request in CommentBar loading test ([62d78f1](https://github.com/eddimull/TTS-App/commit/62d78f1ab0bcff3e849954f44f74b60b163a9a83))
* **questionnaires:** disable navigation for instances without a questionnaire id ([88b05cc](https://github.com/eddimull/TTS-App/commit/88b05cc82ac3f9ffdd61af9d61481f3e5f02183e))
* **questionnaires:** distinguish 409 from other delete failures, surface archive/restore errors ([775baf1](https://github.com/eddimull/TTS-App/commit/775baf1ca5875bd6adbf224dcc6d57d423662ebb))
* **questionnaires:** re-attach provider scope in create sheet modal ([3137f49](https://github.com/eddimull/TTS-App/commit/3137f4918ca5dfa77de516e5e14ff0680bd3d08b))
* **questionnaires:** refresh detail and surface server message on apply-all failure ([241c286](https://github.com/eddimull/TTS-App/commit/241c286f015c621fdce6fee5d8a59a18b9a497c9))
* **questionnaires:** surface load errors, always-visible send tile, prune dead params ([2a61203](https://github.com/eddimull/TTS-App/commit/2a6120379827b45c7cb7e7086f2e6b4a64786aef))
* **questionnaires:** surface server message on append-to-notes failure ([906c4a3](https://github.com/eddimull/TTS-App/commit/906c4a3c4c6cbe12ed7f40116bca922d596cbde2))
* **questionnaires:** tolerate empty-list song_lookup in instance parse ([d537fc6](https://github.com/eddimull/TTS-App/commit/d537fc6facb69676ae70d0d92f8b62675d60c743))
* **realtime:** never throw from pusher onAuthorizer; iOS push fixes ([26e291d](https://github.com/eddimull/TTS-App/commit/26e291d943814ddff7f63d0ad8e3dd52e0940e81))
* **realtime:** pusher onAuthorizer crash on iOS + iOS chat push delivery ([3ef2e42](https://github.com/eddimull/TTS-App/commit/3ef2e42a2b29cc14d0b523e1341bcf59c5e07daf))

## [1.12.0](https://github.com/eddimull/TTS-App/compare/v1.11.0...v1.12.0) (2026-07-14)


### Features

* **chat:** ChatRepository over the conversations API ([9bc24ea](https://github.com/eddimull/TTS-App/commit/9bc24ea48476c23540adf7ba5945b51b70143cfe))
* **chat:** comments sections on event, rehearsal, booking detail ([fc27e49](https://github.com/eddimull/TTS-App/commit/fc27e49ffdbde469d6b40eab2a1790c7ed7b9456))
* **chat:** conversation list + unread total providers ([7ae97e8](https://github.com/eddimull/TTS-App/commit/7ae97e8b8b1c8c738f5b2bd9a5eeabd6bd9aaf25))
* **chat:** conversation thread screen with images, receipts, edit/delete ([b79940a](https://github.com/eddimull/TTS-App/commit/b79940af9573ce6a6fa312a947c97687241f27e7))
* **chat:** conversation/message/participant/contact models + endpoints ([e322524](https://github.com/eddimull/TTS-App/commit/e32252409087355437526c4cfb71ae9cc8ef14ac))
* **chat:** Message in Bandmate action on contact screens ([810193d](https://github.com/eddimull/TTS-App/commit/810193dd570b878673e7d253b9ff37f6f39a17bb))
* **chat:** Messages + New Message screens, routes, More tile with unread badge ([11f747b](https://github.com/eddimull/TTS-App/commit/11f747be8cda22ff5e6232a51ea8525d23ba2770))
* **chat:** thread notifier with live channel, receipts, typing ([205f7af](https://github.com/eddimull/TTS-App/commit/205f7af77272b6ba4ca553f9c0e300299ae6b44e))
* comments & chat — conversations, DMs, comments on events/rehearsals/bookings, realtime, push ([f744c58](https://github.com/eddimull/TTS-App/commit/f744c584d11ea3ed0cdf986188f7b64c6bca1d52))
* **library:** CreateChartArgs route extra prefills chart from a song ([66799e4](https://github.com/eddimull/TTS-App/commit/66799e4f3a18257e8b86f6a355d845bca9e65873))
* **library:** songs↔sheet-music linking on create form and detail screen ([25f8e89](https://github.com/eddimull/TTS-App/commit/25f8e892724ad902668838c100ca6cc927f61cf6))
* **library:** updateChartSong on LibraryNotifier with local state patch ([914f1c4](https://github.com/eddimull/TTS-App/commit/914f1c4ef35e79deb5ee1016cab409e0908043ef))
* nav restructure — Messages tab, Operations hamburger, Settings tab, message-a-bandmate ([16712f1](https://github.com/eddimull/TTS-App/commit/16712f1059e58bea18c78173058e0165f7081be7))
* **nav:** dashboard hamburger opens Operations; one-time bookings-moved hint ([109543c](https://github.com/eddimull/TTS-App/commit/109543c6b0bce46e5a34a57d71c9eeadc76ef716))
* **nav:** Messages tab with unread badge replaces Bookings; More becomes Settings ([25c1d14](https://github.com/eddimull/TTS-App/commit/25c1d142f0880f9877088b7666ca45dc9ecb6726))
* **nav:** messages/operations/settings shell routes, /more redirect ([d258773](https://github.com/eddimull/TTS-App/commit/d258773b3426e15059d176e0cf6ae1126c5b1e5a))
* **nav:** Operations and Settings screens (More split) ([718a0e3](https://github.com/eddimull/TTS-App/commit/718a0e3dcbf5d7bfed585bbdaee44f791158db94))
* **nav:** Song list row on the Operations screen ([479c92b](https://github.com/eddimull/TTS-App/commit/479c92b460c1f2cd5fb6748ad119bda6a2fa0ace))
* **push:** chat_message type routes to thread, suppressed when open ([3139c39](https://github.com/eddimull/TTS-App/commit/3139c396c678f8b30a66ae45e194054981c1e879))
* **realtime:** message signals on band + per-user channels refresh chat ([8bce76c](https://github.com/eddimull/TTS-App/commit/8bce76c36d1ddffc8c4564b7a60b5a1f8b77a4cc))
* song list management, chart linking, and Sheet music relabel ([b3c5a5b](https://github.com/eddimull/TTS-App/commit/b3c5a5b16c8efd988f7138f5756287e2ac85b6fe))
* song-side sheet music linking + fix blank singer picker names ([a20e2fa](https://github.com/eddimull/TTS-App/commit/a20e2fa8b25a2a7b175e8a182dde3df332bfac46))
* **songs:** manage sheet music links from the song detail screen ([8a68be0](https://github.com/eddimull/TTS-App/commit/8a68be0af24b73fbb54393f54cc81508efedd1df))
* **songs:** song create/edit form with BPM lookup, pickers, and steppers ([bade99b](https://github.com/eddimull/TTS-App/commit/bade99b0a70ace870e5ce68fdd99873bf4fff57f))
* **songs:** song detail screen with linked sheet music section ([d71b250](https://github.com/eddimull/TTS-App/commit/d71b250fc761ac9783aefc42605e16dce9836a6d))
* **songs:** song list screen and segmented Library tab (Song list | Sheet music) ([f627e0e](https://github.com/eddimull/TTS-App/commit/f627e0e71e38494cd2e91540031a5c6fac0380c1))
* **songs:** songs AsyncNotifier, inactive filter, band-scoped and lead-singer providers ([e030559](https://github.com/eddimull/TTS-App/commit/e0305598964a425f2669e15a07df0c67762402fe))
* **songs:** songs repository and mobile API endpoints ([bdb5bcc](https://github.com/eddimull/TTS-App/commit/bdb5bcc7a1316b48be481ca45450a43189a753a8))
* **songs:** unified Song model with fromJson/toJson/toUpdateJson ([3fea5f4](https://github.com/eddimull/TTS-App/commit/3fea5f4cb04c5a9558ac13bab9bb4b96a299d917))
* **ui:** relabel user-facing Chart copy as Sheet music ([bce7748](https://github.com/eddimull/TTS-App/commit/bce774870972ac57174a39e74eb2e05981069ac4))


### Bug Fixes

* **auth:** clear chat provider caches on logout to stop cross-user leak ([d79519c](https://github.com/eddimull/TTS-App/commit/d79519c76e63707a13a41a1a09669c4dd03d16c6))
* **chat:** address Copilot review — stable createdAt fallback, suppression-callback ordering ([684411c](https://github.com/eddimull/TTS-App/commit/684411c64eb8e8ed69e192ba25adc8a62f75f823))
* **chat:** autoDispose thread notifier owning channel unsubscribe; mounted guards ([20d55b5](https://github.com/eddimull/TTS-App/commit/20d55b5aceed9ae4a248a19ecdd0b1163e239f91))
* **chat:** band-scope the booking conversation endpoint ([25940f1](https://github.com/eddimull/TTS-App/commit/25940f10f3987c4559bdefb6d5882ba63c6024c8))
* **chat:** only mark-read on others' messages, and debounce it ([7765f0d](https://github.com/eddimull/TTS-App/commit/7765f0d0b734072f76b8b0a7fc938e6230aecc8a))
* **chat:** pre-PR minors — restore-on-failure, doc fix, dead field, cached bytes ([a3cd875](https://github.com/eddimull/TTS-App/commit/a3cd8756db2814d210eb204e38f2cb8b578103a3))
* **chat:** reverse-list the thread to fix loadMore chain-fetch and prepend jump ([8b6f218](https://github.com/eddimull/TTS-App/commit/8b6f218f6b48fffd2dca9ef0e4fcee477c8f288e))
* **library:** refresh songs state after chart link changes ([ba3483d](https://github.com/eddimull/TTS-App/commit/ba3483de41f15abb9cd812ba2e8775fb090b0825))
* **nav:** address Copilot review — mirror shell shape in route-saving harness, accessible hint dismiss ([7ff4d1a](https://github.com/eddimull/TTS-App/commit/7ff4d1aeb20d43f3fed2f9faee11ccc4b7d5f668))
* **nav:** close cold-restore trap into /messages/new composer ([b392436](https://github.com/eddimull/TTS-App/commit/b392436b6335ea9380e3ae01ad45a504ad50b96b))
* **nav:** pre-warm hintStorageProvider in main.dart to avoid hint pop-in ([35de047](https://github.com/eddimull/TTS-App/commit/35de047c10037ef6a920fbfda957a922e91f1590))
* **personnel:** parse display_name so user-linked roster members aren't blank ([c005356](https://github.com/eddimull/TTS-App/commit/c0053568000aee5bb6fb12fb5e9be052620272cb))
* **push:** guard the background handler's plugin calls so failures never escape the isolate ([ba77110](https://github.com/eddimull/TTS-App/commit/ba77110db15cea4549e22f9e266f6787d5696175))
* **push:** render chat_message notifications in the backgrounded FCM isolate ([2934bea](https://github.com/eddimull/TTS-App/commit/2934beaad0fcc3a80053bcc0b498adf99cbf26f7))
* **push:** wire restore-path registration, fix chat suppression, tap deep-link, dev image TLS ([42e09df](https://github.com/eddimull/TTS-App/commit/42e09dfa4748c5aaf0a5a5a1ad3e2a43ebf85c40))
* **songs:** address review feedback — picker error handling, toggle semantics, edit-route fallback ([bd7b912](https://github.com/eddimull/TTS-App/commit/bd7b912dd6acb484d57ff4b57ed04f97c3a088df))
* **songs:** guard setState after awaits and cap BPM input at 3 digits ([9481cc1](https://github.com/eddimull/TTS-App/commit/9481cc17d53256a7f13a257e6a17ea5ac415a2c2))
* **songs:** hold the sheet-music busy guard across the whole link flow ([85749cb](https://github.com/eddimull/TTS-App/commit/85749cb58aa03d467896de35319ab18067b527da))
* **songs:** only safe-area the songs bottom bar on the standalone route ([3d91f77](https://github.com/eddimull/TTS-App/commit/3d91f77547f4c7335d3d47741988f6fb40bb77eb))
* **songs:** re-attach ProviderScope container in modal popups (Copilot review) ([61bf6e7](https://github.com/eddimull/TTS-App/commit/61bf6e73a50bbce4f55a58bcb220f2c26f5bd57d))
* **songs:** safe-area the standalone songs bar and friendly relink errors ([9e3a775](https://github.com/eddimull/TTS-App/commit/9e3a7757e35d8326aab700f999ed68b3dd7e5a7e))

## [1.11.0](https://github.com/eddimull/TTS-App/compare/v1.10.0...v1.11.0) (2026-07-08)


### Features

* **realtime:** activate band realtime subscription from the app shell ([b1ede94](https://github.com/eddimull/TTS-App/commit/b1ede94cafe27e14601984de0b240afa40c70cc2))
* **realtime:** bandRealtimeProvider — band channel signals invalidate feature providers ([3a4bd36](https://github.com/eddimull/TTS-App/commit/3a4bd36cec74dc66c83795bc68948ef61b75afe2))
* **realtime:** media_file signals refresh media lists ([b073352](https://github.com/eddimull/TTS-App/commit/b073352650113d8f646b9bcabe3ea2f13a9d47df))
* **realtime:** payments/payout signals refresh booking detail and payout screens ([edb95c1](https://github.com/eddimull/TTS-App/commit/edb95c1845b5efb62055aaf0d6522024975f0012))
* **realtime:** song and chart signals refresh library, search, and chart screens ([8064381](https://github.com/eddimull/TTS-App/commit/8064381120cd4b88554bd006d20ee76ade13fbf3))


### Bug Fixes

* **realtime:** clear bookings disk cache before invalidating on signal ([9ff37f6](https://github.com/eddimull/TTS-App/commit/9ff37f6adbebcbca43de4644b9613c7095c00be3))
* **realtime:** contain best-effort realtime errors at fire-and-forget boundaries ([f833e83](https://github.com/eddimull/TTS-App/commit/f833e83126a1c24d12dd0e83e50141fda6cefd30))
* **realtime:** init Pusher once per connection; roster signals refresh personnel providers ([d9d3130](https://github.com/eddimull/TTS-App/commit/d9d313019764d78427388892f0a0cad8af0c3289))
* **realtime:** serialize resubscribe with generation guard; no state writes after dispose ([fe48d16](https://github.com/eddimull/TTS-App/commit/fe48d16fac2376f87c2adceddb88011430bb9813))

## [1.10.0](https://github.com/eddimull/TTS-App/compare/v1.9.0...v1.10.0) (2026-07-06)


### Features

* **bookings:** Amend contract action on the locked contract view ([4ac9e56](https://github.com/eddimull/TTS-App/commit/4ac9e56155c147bac0454d3cf5ab22fa940bba3b))
* **bookings:** clarify contract options on the create form ([635f445](https://github.com/eddimull/TTS-App/commit/635f44529e1cc7bdf11a0f0c8694c3791d277e01))
* **bookings:** default blank event titles to the booking name on create ([887ee86](https://github.com/eddimull/TTS-App/commit/887ee8687a53d9cdd2b6aa59ed5c38d8840e504c))
* **bookings:** functional contract-type picker replaces coming-soon stub ([2ae76e8](https://github.com/eddimull/TTS-App/commit/2ae76e82e26a01f929dd2efed0508096d66d3c39))
* **bookings:** guide the contract send flow after saving a booking ([bf0167b](https://github.com/eddimull/TTS-App/commit/bf0167b362620e7e34dfc0f6f63a66ff729e2042))
* **bookings:** land on the new booking's detail screen after create ([9c14cd8](https://github.com/eddimull/TTS-App/commit/9c14cd8bfc05a23779205b477d1d098c8d849a96))
* **bookings:** repository support for contract amendment ([6544168](https://github.com/eddimull/TTS-App/commit/65441686fdee20d5274d6292118f760e134e78d8))
* **bookings:** reserved-dates calendar for the event date picker ([58ef417](https://github.com/eddimull/TTS-App/commit/58ef417834668537c4a6a3813f36ce28de587fd5))
* **push:** rehearsal push types, generic title/body fallback, band_updates channel ([3471d70](https://github.com/eddimull/TTS-App/commit/3471d70cccecb2b28b88b3a7282dfb1e64042eb7))
* **push:** tap-to-open deep-linking for rehearsal pushes ([2bd6ea4](https://github.com/eddimull/TTS-App/commit/2bd6ea43a7ef38b71bd25e47dffb81b83ef65a64))
* **rehearsals:** cancel/restore actions on rehearsal detail screen ([21a3dfa](https://github.com/eddimull/TTS-App/commit/21a3dfa6ecd45ad450e5300f63eaaf5b4cf21b56))
* **rehearsals:** repository setCancelled + endpoint constant ([78fe885](https://github.com/eddimull/TTS-App/commit/78fe885f7fad87198b0a5b7f188fffd305f5a0df))


### Bug Fixes

* **bookings:** re-attach provider container inside the date picker popup ([4b4ee94](https://github.com/eddimull/TTS-App/commit/4b4ee94516ab5f3e0cb3327ed4e08845ca323b80))
* **bookings:** unsent contract tile reads 'Not sent yet' instead of 'Pending' ([74ec65b](https://github.com/eddimull/TTS-App/commit/74ec65bad80b48fa89c246115b8083d1c4095567))
* **media:** show thumbnails for video tiles in the media grid ([dcc3c62](https://github.com/eddimull/TTS-App/commit/dcc3c6222fab17a5bf9671d97e40668076834454))
* **media:** show thumbnails for video tiles in the media grid ([78cfdbe](https://github.com/eddimull/TTS-App/commit/78cfdbe996f3465c7198f80e1bdb2f2013fe62f2))
* **rehearsals:** sync detail state on parent rebuild (didUpdateWidget) ([5d5f7e4](https://github.com/eddimull/TTS-App/commit/5d5f7e4f233d4a518a18a815de179ed8d1d6c78e))
* **rehearsals:** sync notes from setCancelled response unless editing ([e350242](https://github.com/eddimull/TTS-App/commit/e350242d4dfdb336ab35d11b56fff53ddbaf04e9))

## [1.9.0](https://github.com/eddimull/TTS-App/compare/v1.8.0...v1.9.0) (2026-07-04)


### Features

* **social-login:** Android/iOS platform config for provider SDKs ([eb4cfa3](https://github.com/eddimull/TTS-App/commit/eb4cfa37426527b5aa148e884fd7692f3decaef3))
* **social-login:** drop social buttons from welcome screen, keep on login/signup ([139af79](https://github.com/eddimull/TTS-App/commit/139af79f0217e0930ed674f6baa0e4c8995d8702))
* **social-login:** gate Facebook button behind FACEBOOK_LOGIN_ENABLED flag ([50fc9ea](https://github.com/eddimull/TTS-App/commit/50fc9ea2ac9a3081cab9ad4739bd3638e4001918))
* **social-login:** real Facebook app id + client token ([076b155](https://github.com/eddimull/TTS-App/commit/076b15595a8d5d99d03e7b5e6c427b8cab9687d4))
* **social-login:** real iOS Google OAuth client id in Info.plist ([854dcf6](https://github.com/eddimull/TTS-App/commit/854dcf692b92689bcee201dbfcc7feaae5e14324))
* **social-login:** social buttons on welcome/login/signup screens ([8ff487a](https://github.com/eddimull/TTS-App/commit/8ff487a237152821209c9a3e43a614e20e21fad6))


### Bug Fixes

* **social-login:** cancel after failed attempt no longer resurfaces stale error ([d9b506a](https://github.com/eddimull/TTS-App/commit/d9b506ae98d34f926ef3a564d5cf5d068e6e913e))
* **social-login:** guard missing GOOGLE_SERVER_CLIENT_ID; align null-error handling ([5cc9a31](https://github.com/eddimull/TTS-App/commit/5cc9a3161ff21bd4314f095126b933a9ae3d9346))

## [1.8.0](https://github.com/eddimull/TTS-App/compare/v1.7.0...v1.8.0) (2026-07-03)


### Features

* invite QR deep-linking — camera scan opens the app ([#84](https://github.com/eddimull/TTS-App/issues/84)) ([efaa73c](https://github.com/eddimull/TTS-App/commit/efaa73cc43a5d1e9f5ec5fbaa219a23dff59154f))

## [1.7.0](https://github.com/eddimull/TTS-App/compare/v1.6.1...v1.7.0) (2026-07-01)


### Features

* **events:** link an event back to its parent booking ([#76](https://github.com/eddimull/TTS-App/issues/76)) ([c5aabd4](https://github.com/eddimull/TTS-App/commit/c5aabd4bfaeef1b6c31bc5b28e6c4547ec8c01b2))
* **rehearsal-planner:** AI rehearsal planner chat ([#78](https://github.com/eddimull/TTS-App/issues/78)) ([8f7dd7e](https://github.com/eddimull/TTS-App/commit/8f7dd7e266a70f5b7ce73c159dc76dd7a1b428e0))
* **rehearsal-planner:** auto-scroll chat + actionable suggestion chips ([#82](https://github.com/eddimull/TTS-App/issues/82)) ([2f0ec6b](https://github.com/eddimull/TTS-App/commit/2f0ec6b880aa6f4daac2f51cc1821781b342c9d0))
* **rehearsal-planner:** save AI-generated plan to rehearsal notes ([#83](https://github.com/eddimull/TTS-App/issues/83)) ([3502148](https://github.com/eddimull/TTS-App/commit/3502148aa6f5dc281bb78ac5e4214fdd6cc7f558))


### Bug Fixes

* **realtime:** onAuthorizer must POST to /broadcasting/auth and return the auth signature ([#81](https://github.com/eddimull/TTS-App/issues/81)) ([36b5710](https://github.com/eddimull/TTS-App/commit/36b57108e786254a6d2c27b35afb10e16568f479))
* **rehearsal-planner:** type Pusher onEvent param as dynamic for AOT ([#79](https://github.com/eddimull/TTS-App/issues/79)) ([349f4f7](https://github.com/eddimull/TTS-App/commit/349f4f7b4b38097bdaa8b5484188f01f913ba5ed))

## [1.6.1](https://github.com/eddimull/TTS-App/compare/v1.6.0...v1.6.1) (2026-06-30)


### Bug Fixes

* **deploy:** wait for Android Build to finish before promoting (no concurrent Play edits) ([ce27a25](https://github.com/eddimull/TTS-App/commit/ce27a254c3daeed6c4abe27276cf7acbab3c731f))
* **ui:** resolve dark-mode subtext contrast app-wide ([#75](https://github.com/eddimull/TTS-App/issues/75)) ([f7b015f](https://github.com/eddimull/TTS-App/commit/f7b015fa9e63d23469694621eda4ef784b9deadb))

## [1.6.0](https://github.com/eddimull/TTS-App/compare/v1.5.3...v1.6.0) (2026-06-27)


### Features

* **ci:** staging/UAT branch + auto-deploy on release ([ad6c372](https://github.com/eddimull/TTS-App/commit/ad6c372499c10ba6e7711f687582fae535116f37))


### Bug Fixes

* **deploy:** address Copilot review ([28f1522](https://github.com/eddimull/TTS-App/commit/28f1522e937d53b17bbee8136cc5b8fb9af4a589))
* **deploy:** make hands-off production deploy reliable ([ae715a3](https://github.com/eddimull/TTS-App/commit/ae715a33da0062f0363626a4b0c03d4fb4be211a))

## [1.5.3](https://github.com/eddimull/TTS-App/compare/v1.5.2...v1.5.3) (2026-06-27)


### Bug Fixes

* **deploy:** resolve iOS release-notes path independently of fastlane CWD ([df10d3c](https://github.com/eddimull/TTS-App/commit/df10d3c66c5556f6f794fa60f2066d160aebbbb7))
* **deploy:** use access_token_scopes for Play androidpublisher access ([ecc09ce](https://github.com/eddimull/TTS-App/commit/ecc09ce538d30616f14f03c752bed670015deb2f))
* **deploy:** wait for matching internal build before promoting; drop unsafe fallback ([e4c3696](https://github.com/eddimull/TTS-App/commit/e4c36966d06b79eb46afc0cc6d2e7edff43a0b72))

## [1.5.2](https://github.com/eddimull/TTS-App/compare/v1.5.1...v1.5.2) (2026-06-27)


### Bug Fixes

* **deploy:** make store submission idempotent on re-runs ([7c79e64](https://github.com/eddimull/TTS-App/commit/7c79e6437264b9cd1109542db9656fe4a53dbce7))
* **deploy:** unblock App Store + Play production submission ([84600fe](https://github.com/eddimull/TTS-App/commit/84600fedca0c50afa07e85ac7c9336609733b0b4))

## [1.5.1](https://github.com/eddimull/TTS-App/compare/v1.5.0...v1.5.1) (2026-06-27)


### Bug Fixes

* **ci:** add `workflows` permission to sync-deploy-dropdown job ([#58](https://github.com/eddimull/TTS-App/issues/58)) ([9b40096](https://github.com/eddimull/TTS-App/commit/9b40096008fd6be9af05b2bf4f4cdda301c7ea83))

## [1.5.0](https://github.com/eddimull/TTS-App/compare/v1.4.0...v1.5.0) (2026-06-27)


### Features

* **deploy:** release dropdown + resolve job for Release Deploy ([#57](https://github.com/eddimull/TTS-App/issues/57)) ([7f723eb](https://github.com/eddimull/TTS-App/commit/7f723ebafd7814932236e6c5a8a8e7e25bc7a07b))


### Bug Fixes

* **deploy:** repair store uploads and add tag selection to Release Deploy ([#55](https://github.com/eddimull/TTS-App/issues/55)) ([150172f](https://github.com/eddimull/TTS-App/commit/150172f9bf4009e9e67e88aec9d0ff938c73941b))

## [1.4.0](https://github.com/eddimull/TTS-App/compare/v1.3.0...v1.4.0) (2026-06-26)


### Features

* **finances:** revenue tab on mobile (web parity, slice 1) ([#51](https://github.com/eddimull/TTS-App/issues/51)) ([5955da8](https://github.com/eddimull/TTS-App/commit/5955da85df867020f327853505b967d302d85005))
* **finances:** Trends chart + time travel on mobile (web parity, slice 2) ([#53](https://github.com/eddimull/TTS-App/issues/53)) ([8729874](https://github.com/eddimull/TTS-App/commit/8729874e41afe0ba2635fd463398de6eccc7fa56))


### Bug Fixes

* **dashboard:** start the current-month events list from today ([#54](https://github.com/eddimull/TTS-App/issues/54)) ([9a9033c](https://github.com/eddimull/TTS-App/commit/9a9033c1b433661d2792f8192ad21a4a8b3b828d))

## [1.3.0](https://github.com/eddimull/TTS-App/compare/v1.2.0...v1.3.0) (2026-06-26)


### Features

* **dashboard:** show past events on calendar + lazy load-older on swipe-back ([#50](https://github.com/eddimull/TTS-App/issues/50)) ([661747b](https://github.com/eddimull/TTS-App/commit/661747b9697aa7e545c8dd539db8d13a75b91543))
* **release:** automate App Store + Play production submission with release notes ([#49](https://github.com/eddimull/TTS-App/issues/49)) ([03212f8](https://github.com/eddimull/TTS-App/commit/03212f85cca334b5d3a8020c49f5b1f8ee83a4d9))


### Bug Fixes

* **release:** drop mikefarah/yq action; use preinstalled yq ([#47](https://github.com/eddimull/TTS-App/issues/47)) ([024366a](https://github.com/eddimull/TTS-App/commit/024366a2ab8b4480c35d22c3e976c157bc36b726))
