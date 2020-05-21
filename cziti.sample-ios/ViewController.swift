//
//  ViewController.swift
//  cziti.sample-ios
//

import UIKit
import WebKit
import CZiti

class ViewController: UIViewController {
    @IBOutlet weak var urlTextField: UITextField!
    @IBOutlet weak var textView: UITextView!
        
    var ziti:Ziti?
    var zidFile:String {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("zid.json", isDirectory: false).path
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        urlTextField.addTarget(self, action: #selector(onTextFieldDidEndOnExit), for: .editingDidEndOnExit)
        
        if ziti == nil {
            runZiti()
        }
    }
    
    func runZiti() {
        ziti = Ziti(fromFile: zidFile)
        if let ziti = ziti {
            ziti.runAsync { zErr in
                guard zErr == nil else {
                    print("Unable to run Ziti: \(String(describing: zErr!))")
                    self.handleZitiInitError(zErr!)
                    return
                }
                
                ZitiUrlProtocol.register(ziti)
            }
        } else {
            onNoIdentity()
        }
    }
    
    func enroll() {
        DispatchQueue.main.async {
            let dp = UIDocumentPickerViewController(documentTypes: ["public.item"], in: .import)
            dp.modalPresentationStyle = .formSheet
            dp.allowsMultipleSelection = false
            dp.delegate = self
            self.present(dp, animated: true, completion: nil)
        }
    }
    
    func handleZitiInitError(_ zErr:ZitiError) {
        let alert = UIAlertController(
            title:"Ziti Init Error",
            message: "\(zErr.localizedDescription)\n\nWhat do you want to do now?",
            preferredStyle: .alert)
        
        alert.addAction(UIAlertAction(
            title: NSLocalizedString("Retry", comment: "Retry"),
            style: .default,
            handler: { _ in
                self.runZiti()
        }))
        
        alert.addAction(UIAlertAction(
            title: NSLocalizedString("Forget This Identity", comment: "Forget"),
            style: .destructive,
            handler: { _ in
                if let ziti = self.ziti {
                    ziti.forget()
                }
                try? FileManager.default.removeItem(atPath: self.zidFile)
                self.onNoIdentity()
        }))
        
        alert.addAction(UIAlertAction(
            title: NSLocalizedString("Exit", comment: "Exit"),
            style: .default,
            handler: { _ in
                exit(1)
        }))
        
        DispatchQueue.main.async {
            self.present(alert, animated: true, completion: nil)
        }
    }
    
    func onNoIdentity() {
        let alert = UIAlertController(
            title:"Ziti Identity Not Found",
            message: "What do you want to do now?",
            preferredStyle: .alert)
        
        alert.addAction(UIAlertAction(
            title: NSLocalizedString("Enroll", comment: "Enroll"),
            style: .default,
            handler: { _ in
                self.enroll()
        }))
        
        alert.addAction(UIAlertAction(
            title: NSLocalizedString("Exit", comment: "Exit"),
            style: .default,
            handler: { _ in
                exit(1)
        }))
        
        DispatchQueue.main.async {
            self.present(alert, animated: true, completion: nil)
        }
    }
    
    @objc func onTextFieldDidEndOnExit(){
        if let text = urlTextField.text, let url = URL(string: text) {
            let urlReq = URLRequest(url: url)
            let zitiCanHandle = ZitiUrlProtocol.canInit(with: urlReq)
            
            if !zitiCanHandle {
                let alert = UIAlertController(
                    title:"Not a Ziti request",
                    message: "This request will not be routed over your Ziti nework.\nAre you sure you'd like to request this URL?",
                    preferredStyle: .alert)
                
                alert.addAction(UIAlertAction(
                    title: NSLocalizedString("OK", comment: "Default action"),
                    style: .default,
                    handler: { _ in
                        self.loadUrl(urlReq)
                }))
                
                alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "Cancel"), style: .cancel))
                present(alert, animated: true, completion: nil)
            } else {
                self.loadUrl(urlReq)
            }
        }
        urlTextField.resignFirstResponder()
    }
    func setScrollableText(_ txt: String) {
        DispatchQueue.main.async {
            self.textView.textStorage.mutableString.setString(txt)
        }
    }
    
    func loadUrl(_ urlReq:URLRequest) {
        URLSession.shared.dataTask(with: urlReq) { (data, response, error) in
            guard error == nil else {
                self.setScrollableText(error!.localizedDescription)
                return
            }
            
            var docStr = ""
            if let response = response as? HTTPURLResponse {
                docStr += "Status: \(response.statusCode) " +
                    "(\(HTTPURLResponse.localizedString(forStatusCode: response.statusCode)))\n" +
                    response.allHeaderFields.compactMap {
                        "\($0): \($1)\n"
                    }.joined() + "\n"
            }
            
            if let data = data, let str = String(data: data, encoding: .utf8)  {
                docStr += str
            } else {
                docStr += "...Unable to decode body to string..."
            }
            self.setScrollableText(docStr)
        }.resume()
    }
}

extension ViewController : UIDocumentPickerDelegate {
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        onNoIdentity()
    }
    
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        
        Ziti.enroll(urls[0].path) { zid, zErr in
            guard let zid = zid, zErr == nil else {
                let alert = UIAlertController(
                    title:"Enrollment Error",
                    message: zErr?.localizedDescription ?? "",
                    preferredStyle: .alert)
                
                alert.addAction(UIAlertAction(
                    title: NSLocalizedString("OK", comment: "Default action"),
                    style: .default,
                    handler: { _ in
                        self.onNoIdentity()
                }))
                
                self.present(alert, animated: true, completion: nil)
                return
            }
            
            // Store zid @ zidFile
            guard zid.save(self.zidFile) else {
                let alert = UIAlertController(
                    title:"Unable to store identity file",
                    message: self.zidFile,
                    preferredStyle: .alert)
                
                alert.addAction(UIAlertAction(
                    title: NSLocalizedString("OK", comment: "Default action"),
                    style: .default,
                    handler: { _ in
                        self.onNoIdentity()
                }))
                
                self.present(alert, animated: true, completion: nil)
                return
            }
            
            let alert = UIAlertController(
                title:"Enrolled!",
                message: "You have successfully enrolled id: \(zid.id)",
                preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Default action"), style: .default))
            self.present(alert, animated: true, completion: nil)
            self.runZiti()
        }
    }
}

extension ViewController : WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        let alert = UIAlertController(
            title:"Navigation failed",
            message: error.localizedDescription,
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Default action"), style: .default))
        self.present(alert, animated: true, completion: nil)
    }
    
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let alert = UIAlertController(
            title:"Provisional Navigation Failed",
            message: error.localizedDescription,
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Default action"), style: .default))
        self.present(alert, animated: true, completion: nil)
    }
}
