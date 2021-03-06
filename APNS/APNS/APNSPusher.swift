import Cocoa
import Foundation
import CupertinoJWT

public enum APNSPusherType {
    case none, certificate(identity: SecIdentity), token(keyID: String, teamID: String, p8: String)
}

public protocol APNSPushable {
    var type: APNSPusherType { get set }
    var identity: SecIdentity? { get }
    func pushPayload(_ payload: Dictionary<String, Any>,
                     to token: String,
                     withTopic topic: String?,
                     priority: Int,
                     collapseID: String?,
                     inSandbox sandbox: Bool,
                     completion: @escaping (Result<String, Error>) -> Void)
}

public final class APNSPusher: NSObject, APNSPushable {
    public var type: APNSPusherType {
        didSet {
            switch type {
            case .certificate(let _identity):
                identity = _identity
                session = URLSession(configuration: .default,
                                     delegate: self,
                                     delegateQueue: .main)
            case .token:
                session = URLSession(configuration: .default,
                                     delegate: nil,
                                     delegateQueue: .main)
            case .none: ()
            }
        }
    }
    private var _identity: SecIdentity?
    private var session: URLSession?
    
    public private(set) var identity: SecIdentity? {
        get {
            return _identity
        }
        
        set(value) {
            if _identity != value {
                if _identity != nil {
                    _identity = nil
                }
                
                if value != nil {
                    _identity = value
                    
                } else {
                    _identity = nil
                }
            }
        }
    }
    
    public override init() {
        self.type = .none
        super.init()
    }
    
    public func pushPayload(_ payload: Dictionary<String, Any>,
                            to token: String,
                            withTopic topic: String?,
                            priority: Int,
                            collapseID: String?,
                            inSandbox sandbox: Bool,
                            completion: @escaping (Result<String, Error>) -> Void){
        guard let url = URL(string: "https://api\(sandbox ? ".development" : "").push.apple.com/3/device/\(token)") else {
            completion(.failure(NSError(domain: "com.pusher.APNSPusher", code: 0, userInfo: [NSLocalizedDescriptionKey: "URL error"])))
            return
        }
        
        guard let httpBody = try? JSONSerialization.data(withJSONObject: payload, options: .prettyPrinted) else {
            completion(.failure(NSError(domain: "com.pusher.APNSPusher", code: 0, userInfo: [NSLocalizedDescriptionKey: "Payload error"])))
            return
        }
        
        var request = URLRequest(url: url)
        
        request.httpMethod = "POST"
        
        request.httpBody = httpBody
        
        if let topic = topic {
            request.addValue(topic, forHTTPHeaderField: "apns-topic")
        }
        
        if let collapseID = collapseID, collapseID.count > 0 {
            request.addValue(collapseID, forHTTPHeaderField: "apns-collapse-id")
        }
        
        request.addValue("\(priority)", forHTTPHeaderField: "apns-priority")
        
        if case .token(let keyID, let teamID, let p8) = type {
            // Assign developer information and token expiration setting
            let jwt = JWT(keyID: keyID,
                          teamID: teamID,
                          issueDate: Date(),
                          expireDuration: 60 * 60)
            
            if let authToken = try? jwt.sign(with: p8) {
                request.addValue("bearer \(authToken)", forHTTPHeaderField: "authorization")
            }
        }
        
        session?.dataTask(with: request, completionHandler: { (data, response, error) in
            guard let r = response as? HTTPURLResponse else {
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "com.pusher.APNSPusher", code: 0, userInfo: [NSLocalizedDescriptionKey: "Unknown error"])))
                }
                return
            }
            
            if let error = error {
                DispatchQueue.main.async {
                    completion(.failure(error as NSError))
                }
                return
            }
            
            switch r.statusCode {
            case 200:
                DispatchQueue.main.async {
                    completion(.success(HTTPURLResponse.localizedString(forStatusCode: r.statusCode)))
                }
                
            default:
                if let data = data,
                    let dict = try? JSONSerialization.jsonObject(with: data, options: JSONSerialization.ReadingOptions.allowFragments),
                    let json = dict as? [String: Any],
                    let reason = json["reason"] as? String {
                    DispatchQueue.main.async {
                        completion(.failure(NSError(domain: "com.pusher.APNSPusher", code: r.statusCode, userInfo: [NSLocalizedDescriptionKey: reason])))
                    }
                    
                } else {
                    DispatchQueue.main.async {
                        completion(.failure(NSError(domain: "com.pusher.APNSPusher", code: r.statusCode, userInfo: [NSLocalizedDescriptionKey: HTTPURLResponse.localizedString(forStatusCode: r.statusCode)])))
                    }
                }
            }
        }).resume()
    }
}

extension APNSPusher: URLSessionDelegate {
    public func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard let identityNotNil = _identity else {
            return
        }
        var certificate: SecCertificate?
        
        SecIdentityCopyCertificate(identityNotNil, &certificate)
        
        guard let cert = certificate else {
            return
        }
        
        let cred = URLCredential(identity: identityNotNil, certificates: [cert], persistence: .forSession)
        
        certificate = nil
        
        completionHandler(.useCredential, cred)
    }
}
