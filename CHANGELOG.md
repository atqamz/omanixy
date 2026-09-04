# Changelog

## [0.2.0](https://github.com/atqamz/omanixy/compare/v0.1.0...v0.2.0) (2026-09-04)


### Features

* **shell:** present monitor-local workspace grids ([#77](https://github.com/atqamz/omanixy/issues/77)) ([84e8d19](https://github.com/atqamz/omanixy/commit/84e8d19088fb78e811839b07b93408a62e98522d))

## 0.1.0 (2026-08-31)


### Features

* **home:** merge nested shell configuration recursively ([#48](https://github.com/atqamz/omanixy/issues/48)) ([918113d](https://github.com/atqamz/omanixy/commit/918113d8d6ca0f7c7ae70d587459188b1697ba79))
* **launcher:** provision xdg terminal execution ([#54](https://github.com/atqamz/omanixy/issues/54)) ([c8f8711](https://github.com/atqamz/omanixy/commit/c8f87110ec1d4a05fde28d6e8061f315f60b3db4))
* **omanixy-shell:** add Quattro compatibility contracts and Nix-native adapters ([29311d9](https://github.com/atqamz/omanixy/commit/29311d9621c6dff47cf4b3196c4e9891b6493f57)), closes [#3](https://github.com/atqamz/omanixy/issues/3)
* **presentation:** own default font and wallpaper ([#45](https://github.com/atqamz/omanixy/issues/45)) ([10fa084](https://github.com/atqamz/omanixy/commit/10fa084e38562b0f4e1b839e0a051809a4ceefc2))
* **runtime:** run pinned Quattro shell ([#9](https://github.com/atqamz/omanixy/issues/9)) ([c756f85](https://github.com/atqamz/omanixy/commit/c756f85dc2ad546fa2cfbad1fdf3b51913bc6723))
* **security:** add bounded fingerprint lock capability ([#15](https://github.com/atqamz/omanixy/issues/15)) ([5d52182](https://github.com/atqamz/omanixy/commit/5d52182a8be1ffd4a39ba76a91fa738c1c06f491))
* **security:** add bounded Quattro idle ownership ([#17](https://github.com/atqamz/omanixy/issues/17)) ([9093a32](https://github.com/atqamz/omanixy/commit/9093a324afc1c7fe23ca14bb1db4c3ac3deb53c1))
* **security:** add declarative password-only native session lock ([#14](https://github.com/atqamz/omanixy/issues/14)) ([4d313e2](https://github.com/atqamz/omanixy/commit/4d313e2283821e504621f7aed94458ac5ddf697e))
* **security:** add explicit Quattro notification daemon ownership ([#18](https://github.com/atqamz/omanixy/issues/18)) ([ccc7e4e](https://github.com/atqamz/omanixy/commit/ccc7e4ecc4fcd99518c7c299beff5e84f3d6b228))
* **security:** add explicit Quattro polkit agent ownership ([#16](https://github.com/atqamz/omanixy/issues/16)) ([6796153](https://github.com/atqamz/omanixy/commit/67961531e0c6e6e6734ba7ee1c2f1e54f144d6d8))
* **security:** declarative NixOS PAM password capability ([#12](https://github.com/atqamz/omanixy/issues/12)) ([e68ec86](https://github.com/atqamz/omanixy/commit/e68ec86eee247c2069173d3c6eb044ec55fb211c))


### Bug Fixes

* **adoption:** preserve baseline in partial shell config ([#37](https://github.com/atqamz/omanixy/issues/37)) ([6eee2f5](https://github.com/atqamz/omanixy/commit/6eee2f50c5865747a6c7d028b28771ad93db7b12))
* **background:** close wallpaper ownership gaps ([#60](https://github.com/atqamz/omanixy/issues/60)) ([abb0d48](https://github.com/atqamz/omanixy/commit/abb0d485365c26eb955a99779d27d4a2116fdc7c))
* **contract-closure:** report marker check failures accurately ([#47](https://github.com/atqamz/omanixy/issues/47)) ([a287bee](https://github.com/atqamz/omanixy/commit/a287beefcf52c1494ba05b7f0d5a488645cfce7c))
* **home:** provision pinned Omarchy icon font ([#52](https://github.com/atqamz/omanixy/issues/52)) ([da07f7b](https://github.com/atqamz/omanixy/commit/da07f7b8c55a701643c4b737fbfb4f0e24ab1198))
* **launcher:** expose terminal handler to user services ([#55](https://github.com/atqamz/omanixy/issues/55)) ([f99a2d5](https://github.com/atqamz/omanixy/commit/f99a2d50ff81630abd06a5180fc7f619a70ff555))
* **launcher:** restore deterministic app activation ([#40](https://github.com/atqamz/omanixy/issues/40)) ([e7465a2](https://github.com/atqamz/omanixy/commit/e7465a26ce014a3e7c4df9ca54045653b2459821))
* **omanixy-shell:** preserve cold-launched apps after gtk-launch exits ([#53](https://github.com/atqamz/omanixy/issues/53)) ([746c1a5](https://github.com/atqamz/omanixy/commit/746c1a591ac32fc86d89221fa5ff0f23996e5888))
* **release:** align publish configuration ([#67](https://github.com/atqamz/omanixy/issues/67)) ([b0218e7](https://github.com/atqamz/omanixy/commit/b0218e7be35b50fe3fe87ef874be7deaa5ce53b1))
* **release:** normalize bot login in publish guards ([#63](https://github.com/atqamz/omanixy/issues/63)) ([b17681a](https://github.com/atqamz/omanixy/commit/b17681a5c46fcf7ea3b55c361a3072d715c88db6))
* **release:** publish validated releases after main advances ([#65](https://github.com/atqamz/omanixy/issues/65)) ([1439851](https://github.com/atqamz/omanixy/commit/1439851ac3b031ef02741f7ad9039b1ffbd21cbc))
* **security:** stop stale PAM retry notifiers ([#61](https://github.com/atqamz/omanixy/issues/61)) ([d2183ac](https://github.com/atqamz/omanixy/commit/d2183ac96964fbe4d4d8830c86519525dcfaef35))

### Upstream

- Omarchy Quattro: `f0020448ca87329199de7cb12f2015ebc4a3e5e7`
- Quickshell: `28771c7c74b42e20afca0b1b63980cb46515537c`
- nixpkgs: `241313f4e8e508cb9b13278c2b0fa25b9ca27163`

### Compatibility

- Classification counts:
- exact: 7
- adapted: 26
- omitted: 6
- blocked: 0
- Support counts:
- supported: 0
- experimental: 7
- omitted: 0
- blocked: 0
- Security posture: 7 security/session entries remain experimental, opt-in, and disabled by default; none are supported.
- Full ledger: [upstream/porting-matrix.yaml](https://github.com/atqamz/omanixy/blob/v0.1.0/upstream/porting-matrix.yaml)
## Changelog
