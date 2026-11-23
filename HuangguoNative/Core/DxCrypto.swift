import Foundation
import CryptoKit
import CommonCrypto
import Security

/// dx150-edge-v1 加密原语 + 图片 AES-CBC（对齐 Android DxCrypto.kt）
public class DxCrypto {
	private static let imageKey = Array("f5d965df75336270".utf8)
	private static let imageIV = Array("97b60394abc2fbe1".utf8)

	private static var scopeTicket: [String: Int] = [:]
	private static var scopeServing: [String: Int] = [:]
	private static let lock = NSLock()

	public static func nextScopeTicket(_ scope: String) -> Int {
		lock.lock()
		defer { lock.unlock() }
		let next = (scopeTicket[scope] ?? 0) + 1
		scopeTicket[scope] = next
		return next
	}

	public static func scopeServing(_ scope: String) -> Int {
		lock.lock()
		defer { lock.unlock() }
		return scopeServing[scope] ?? 0
	}

	public static func advanceScopeServing(_ scope: String, _ ticket: Int) {
		lock.lock()
		defer { lock.unlock() }
		scopeServing[scope] = ticket
	}

	public static func randomHex(_ byteLenStr: String) -> String {
		let byteLen = Int(byteLenStr) ?? 16
		var bytes = [UInt8](repeating: 0, count: byteLen)
		_ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
		return bytes.map { String(format: "%02x", $0) }.joined()
	}

	/// {"priv":"<std b64 d>","pub":"<b64url 0x04||X||Y>"}
	public static func generateClientKeyPair() -> String {
		let priv = P256.KeyAgreement.PrivateKey()
		let d = priv.rawRepresentation
		let pub = priv.publicKey.x963Representation // 65 bytes 0x04||X||Y
		let obj: [String: String] = [
			"priv": d.base64EncodedString(),
			"pub": base64Url(pub)
		]
		return jsonString(obj)
	}

	/// {"req":"<std b64>","res":"<std b64>","info":"..."}
	public static func deriveSessionKeys(
		_ privB64: String,
		_ serverPubB64url: String,
		_ saltB64url: String,
		_ scope: String,
		_ site: String,
		_ kid: String,
		_ sid: String
	) -> String {
		guard let d = Data(base64Encoded: privB64),
			  let serverPub = dataFromBase64Url(serverPubB64url),
			  let salt = dataFromBase64Url(saltB64url) else {
			return "{\"req\":\"\",\"res\":\"\",\"info\":\"\"}"
		}
		do {
			let priv = try P256.KeyAgreement.PrivateKey(rawRepresentation: d)
			let pub = try P256.KeyAgreement.PublicKey(x963Representation: serverPub)
			let shared = try priv.sharedSecretFromKeyAgreement(with: pub)
			let sharedX = shared.withUnsafeBytes { Data($0) }
			let infoBase = "dx150-edge-v1\n\(scope)\n\(site)\n\(kid)\n\(sid)"
			let reqKey = hkdfSha256(ikm: sharedX, salt: salt, info: Data((infoBase + "\nreq").utf8), length: 32)
			let resKey = hkdfSha256(ikm: sharedX, salt: salt, info: Data((infoBase + "\nres").utf8), length: 32)
			let obj: [String: String] = [
				"req": reqKey.base64EncodedString(),
				"res": resKey.base64EncodedString(),
				"info": infoBase
			]
			return jsonString(obj)
		} catch {
			return "{\"req\":\"\",\"res\":\"\",\"info\":\"\"}"
		}
	}

	public static func aesGcmEncrypt(_ keyB64: String, _ seqStr: String, _ aadUtf8: String, _ plaintextUtf8: String) -> String {
		guard let key = Data(base64Encoded: keyB64), let seq = Int(seqStr) else { return "" }
		let iv = buildIv(seq)
		do {
			let sealed = try AES.GCM.seal(
				Data(plaintextUtf8.utf8),
				using: SymmetricKey(data: key),
				nonce: AES.GCM.Nonce(data: iv),
				authenticating: Data(aadUtf8.utf8)
			)
			// Android Cipher GCM doFinal → ciphertext || tag
			var out = sealed.ciphertext
			out.append(sealed.tag)
			return base64Url(out)
		} catch {
			return ""
		}
	}

	public static func aesGcmDecrypt(_ keyB64: String, _ seqStr: String, _ aadUtf8: String, _ ciphertextB64url: String) -> String {
		guard let key = Data(base64Encoded: keyB64),
			  let seq = Int(seqStr),
			  let ct = dataFromBase64Url(ciphertextB64url),
			  ct.count > 16 else { return "" }
		let iv = buildIv(seq)
		let cipher = ct.prefix(ct.count - 16)
		let tag = ct.suffix(16)
		do {
			let box = try AES.GCM.SealedBox(
				nonce: AES.GCM.Nonce(data: iv),
				ciphertext: cipher,
				tag: tag
			)
			let plain = try AES.GCM.open(box, using: SymmetricKey(data: key), authenticating: Data(aadUtf8.utf8))
			return String(data: plain, encoding: .utf8) ?? ""
		} catch {
			return ""
		}
	}

	public static func decryptImageAesCbc(_ cipherStdB64: String) -> String {
		guard let ct = Data(base64Encoded: cipherStdB64),
			  let plain = try? decryptImageBytesSmart(ct) else {
			return ""
		}
		return plain.base64EncodedString()
	}

	/// 原生工程用：直接对 CDN 原始字节做智能解密
	public static func decryptImageData(_ raw: Data) throws -> Data {
		try decryptImageBytesSmart(raw)
	}

	public static func fetchDecryptImageToFile(_ url: String, _ cacheDir: String) -> String {
		guard let u = URL(string: url) else {
			fatalError("bad image url")
		}
		var req = URLRequest(url: u, timeoutInterval: 25)
		req.setValue("https://huangguoai.com/", forHTTPHeaderField: "Referer")
		req.setValue("HuangguoAndroid/1.0", forHTTPHeaderField: "User-Agent")
		let sem = DispatchSemaphore(value: 0)
		var rawData: Data?
		var httpCode = 0
		var netErr: Error?
		URLSession.shared.dataTask(with: req) { data, resp, err in
			netErr = err
			httpCode = (resp as? HTTPURLResponse)?.statusCode ?? 0
			rawData = data
			sem.signal()
		}.resume()
		_ = sem.wait(timeout: .now() + 30)
		if let netErr = netErr { fatalError("\(netErr)") }
		guard httpCode >= 200 && httpCode < 300, let raw = rawData else {
			fatalError("image http \(httpCode)")
		}
		let plain = try! decryptImageBytesSmart(raw)
		let dir = (cacheDir as NSString)
		try? FileManager.default.createDirectory(atPath: cacheDir, withIntermediateDirectories: true)
		let name = "hg_\(String(url.hashValue, radix: 16))_\(Int(Date().timeIntervalSince1970 * 1000))\(imageExt(plain))"
		let path = dir.appendingPathComponent(name)
		try! plain.write(to: URL(fileURLWithPath: path))
		return path
	}

	public static func stdB64EncodeUtf8(_ text: String) -> String {
		return Data(text.utf8).base64EncodedString()
	}

	public static func stdB64DecodeToUtf8(_ b64: String) -> String {
		guard let data = Data(base64Encoded: b64) else { return "" }
		return String(data: data, encoding: .utf8) ?? ""
	}

	// MARK: - private

	private static func decryptImageBytesSmart(_ raw: Data) throws -> Data {
		if isImageMagic(raw) { return raw }
		guard raw.count >= 16 else { throw NSError(domain: "hg-edge", code: 1, userInfo: [NSLocalizedDescriptionKey: "image too short"]) }
		if let plain = aesCbcDecrypt(raw, pkcs7: true), isImageMagic(plain) {
			return plain
		}
		let aligned = raw.count - (raw.count % 16)
		guard aligned >= 16 else { throw NSError(domain: "hg-edge", code: 2, userInfo: [NSLocalizedDescriptionKey: "image block invalid"]) }
		let block = aligned == raw.count ? raw : raw.prefix(aligned)
		if let plain = aesCbcDecrypt(Data(block), pkcs7: false) {
			if isImageMagic(plain) { return plain }
			let trimmed = stripTrailingPadding(plain)
			if isImageMagic(trimmed) { return trimmed }
		}
		throw NSError(domain: "hg-edge", code: 3, userInfo: [NSLocalizedDescriptionKey: "decrypt not image"])
	}

	private static func aesCbcDecrypt(_ data: Data, pkcs7: Bool) -> Data? {
		var out = Data(count: data.count + kCCBlockSizeAES128)
		let outCapacity = out.count
		var outLen = 0
		let status = out.withUnsafeMutableBytes { outBytes in
			data.withUnsafeBytes { inBytes in
				imageKey.withUnsafeBufferPointer { keyPtr in
					imageIV.withUnsafeBufferPointer { ivPtr in
						CCCrypt(
							CCOperation(kCCDecrypt),
							CCAlgorithm(kCCAlgorithmAES),
							CCOptions(pkcs7 ? kCCOptionPKCS7Padding : 0),
							keyPtr.baseAddress, kCCKeySizeAES128,
							ivPtr.baseAddress,
							inBytes.baseAddress, data.count,
							outBytes.baseAddress, outCapacity,
							&outLen
						)
					}
				}
			}
		}
		guard status == kCCSuccess else { return nil }
		return out.prefix(outLen)
	}

	private static func isImageMagic(_ b: Data) -> Bool {
		guard b.count >= 3 else { return false }
		let a = [UInt8](b.prefix(12))
		if a[0] == 0xFF && a[1] == 0xD8 && a[2] == 0xFF { return true }
		if a.count >= 8 && a[0] == 0x89 && a[1] == 0x50 && a[2] == 0x4E && a[3] == 0x47 { return true }
		if a[0] == 0x47 && a[1] == 0x49 && a[2] == 0x46 { return true }
		if a.count >= 12 && a[0] == 0x52 && a[1] == 0x49 && a[2] == 0x46 && a[3] == 0x46 &&
			a[8] == 0x57 && a[9] == 0x45 && a[10] == 0x42 && a[11] == 0x50 { return true }
		return false
	}

	private static func stripTrailingPadding(_ b: Data) -> Data {
		guard let last = b.last else { return b }
		let pad = Int(last)
		guard pad >= 1 && pad <= 16 && pad <= b.count else { return b }
		let suffix = b.suffix(pad)
		if suffix.allSatisfy({ $0 == last }) {
			return b.prefix(b.count - pad)
		}
		return b
	}

	private static func imageExt(_ b: Data) -> String {
		let a = [UInt8](b.prefix(12))
		if a.count >= 3 && a[0] == 0xFF && a[1] == 0xD8 { return ".jpg" }
		if a.count >= 4 && a[0] == 0x89 && a[1] == 0x50 { return ".png" }
		if a.count >= 12 && a[8] == 0x57 && a[9] == 0x45 { return ".webp" }
		return ".jpg"
	}

	private static func buildIv(_ seq: Int) -> Data {
		var iv = Data(count: 12)
		iv[8] = UInt8((seq >> 24) & 0xff)
		iv[9] = UInt8((seq >> 16) & 0xff)
		iv[10] = UInt8((seq >> 8) & 0xff)
		iv[11] = UInt8(seq & 0xff)
		return iv
	}

	private static func hkdfSha256(ikm: Data, salt: Data, info: Data, length: Int) -> Data {
		let key = SymmetricKey(data: salt)
		let prk = HMAC<SHA256>.authenticationCode(for: ikm, using: key)
		var mac = HMAC<SHA256>(key: SymmetricKey(data: Data(prk)))
		mac.update(data: info)
		mac.update(data: Data([0x01]))
		let okm = Data(mac.finalize())
		return okm.prefix(length)
	}

	private static func base64Url(_ data: Data) -> String {
		data.base64EncodedString()
			.replacingOccurrences(of: "+", with: "-")
			.replacingOccurrences(of: "/", with: "_")
			.replacingOccurrences(of: "=", with: "")
	}

	private static func dataFromBase64Url(_ s: String) -> Data? {
		var b64 = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
		let pad = (4 - b64.count % 4) % 4
		if pad > 0 { b64 += String(repeating: "=", count: pad) }
		return Data(base64Encoded: b64)
	}

	private static func jsonString(_ obj: [String: String]) -> String {
		guard let data = try? JSONSerialization.data(withJSONObject: obj, options: []),
			  let s = String(data: data, encoding: .utf8) else {
			return "{}"
		}
		return s
	}
}
