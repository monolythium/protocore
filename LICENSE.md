# Monolythium Protocore — Preview Binary License (v1)

**Effective:** 2026-05-25
**Licensor:** Mono Labs R&D LLC ("Mono Labs"), a California limited liability company, in coordination with the Monolythium Foundation (Cayman Islands).
**Subject:** The signed binary releases published in this repository (the *"Binaries"*).

---

## 1. Status — interim license

This is a **preview** license for the pre-mainnet window. It governs only the Binaries — the corresponding source code is currently maintained in a private repository owned by Mono Labs.

Mono Labs has publicly committed to release the source code for `protocore` under the **[Business Source License 1.1](https://mariadb.com/bsl11/)** ("BSL-1.1") at Monolythium v2 mainnet activation. BSL-1.1 makes the source available for any use except offering a competing managed commercial service, and converts automatically to a permissive open-source license after four years.

This Preview Binary License is the interim instrument that lets external operators run real testnet infrastructure today without waiting for the mainnet source release.

## 2. Grant

Subject to compliance with the restrictions in §3, Mono Labs grants you a worldwide, royalty-free, non-exclusive, non-transferable, non-sublicensable license to:

1. **Download** any Binary released in this repository.
2. **Run** any Binary for any of the following purposes:
   - Personal use, evaluation, and study.
   - Operating one or more Monolythium operator nodes on the public **testnet** chain.
   - Internal development and integration work against the public testnet.
3. **Verify** the integrity of any Binary using its published SHA-256 checksum, cosign signature, and SBOM.

## 3. Restrictions

You may not:

1. **Redistribute** the Binaries — except by linking to this repository's GitHub Releases page. You may not host the Binaries on other servers, mirrors, or package repositories without prior written consent from Mono Labs.
2. **Modify the Binaries.** Patching, instrumenting, repackaging, or otherwise altering a Binary before redistribution is prohibited. Running an unmodified Binary in your own environment is permitted under §2.
3. **Reverse engineer, decompile, or disassemble** the Binaries for the purpose of producing a competing implementation, library, or managed service. (Reverse engineering for personal study, security research, or interoperability with public Monolythium specifications is permitted — see §4.)
4. **Operate a Binary on mainnet.** Mainnet operation requires a separate signed release under the future BSL-1.1 license. Running an interim Preview Binary against a production chain that has not been declared mainnet by the Monolythium Foundation is prohibited.
5. **Remove, alter, or obscure** the version string, build attestation, signature material, or any other authentication or identification information embedded in a Binary.
6. **Use the Binaries to build or operate a competing Layer-1 blockchain** that re-uses Monolythium's protocol, address format, naming registry, or consensus design without independent re-derivation.

## 4. Security research + interoperability

Nothing in §3 limits good-faith security research, vulnerability disclosure, or interoperability work that publishes its findings against the public Monolythium specifications (whitepaper, ADRs, public SDK).

If you find a vulnerability please email `security@monolythium.com` — see the README's Security section for the disclosure flow.

## 5. Trademarks

This license does not grant any right to use the names "Monolythium", "Mono Labs", "Monolythium Foundation", "Monarch", "protocore", "Lyth", "LYTH", "Mono v2", "LythiumDAG-BFT", or any associated logos, in advertising, publicity, or product naming, except to truthfully identify that you are running unmodified Monolythium Binaries.

## 6. No warranty

THE BINARIES ARE PROVIDED **"AS IS"**, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES, OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT, OR OTHERWISE, ARISING FROM, OUT OF, OR IN CONNECTION WITH THE BINARIES OR THE USE OR OTHER DEALINGS IN THE BINARIES.

In particular, you assume all risk of operating a node, holding LYTH, signing transactions, or relying on chain finality. Mono Labs and the Monolythium Foundation make no representation about the availability, correctness, or security of the public testnet.

## 7. Automatic termination

If you breach §3, this license terminates automatically. On termination you must cease running and delete all copies of the Binaries within your control. Sections 5, 6, and 8 survive termination.

## 8. Future replacement

When the source code for `protocore` is released under BSL-1.1, the corresponding binary release(s) on this repository will be re-published under BSL-1.1 (or such other open-source license as the source is released under). At that point this Preview Binary License is superseded for all future releases. Releases tagged before that transition remain governed by this license for their original lifetime.

## 9. Governing law

This license is governed by the laws of the State of California, USA, without regard to its conflict-of-laws principles. Any dispute arising under this license shall be resolved in the state or federal courts located in San Francisco County, California.

## 10. Contact

- **Licensing exceptions** (commercial distribution, mainnet preview access, evaluation NDA, etc.): `licensing@monolythium.com`
- **Security reports**: `security@monolythium.com`
- **General**: <https://monolythium.com>

---

*This is a plain-English preview license; it has not been through a formal legal review. It will be replaced when source is released. If you are a corporate operator with specific compliance requirements, contact licensing before deploying.*
