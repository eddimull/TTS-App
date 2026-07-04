# Changelog

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
