import UIKit
import WebKit

/* نسخة الآيفون: صفحة البرنامج المنشورة (madeed-clinic.web.app) داخل تطبيق.
   ليست نسخة ثانية من البرنامج: ما يُنشر على الويب يصل الآيفون وحده بلا بناء جديد.
   والنطاق «مرتبط بالتطبيق» (WKAppBoundDomains)، فيعمل الـ Service Worker فيه،
   فيفتح بلا إنترنت ويحفظ ما يُكتب ثم يرفعه كما في Safari.

   وما لا يفعله WKWebView وحده ويحتاجه البرنامج:
   • alert / confirm / prompt — بلا معالج تختفي بصمت (رسائل «احفظ أولاً»…)
   • الطباعة — نافذة الإيصال تُعرض ثم تُطبع بطابعة الآيفون (AirPrint)
   • التنزيلات (نسخة احتياطية، Excel) — تُحفظ ثم تُفتح قائمة المشاركة
   • واتساب والاتصال والروابط الخارجية — تُفتح في تطبيقاتها */
final class WebViewController: UIViewController, WKNavigationDelegate, WKUIDelegate,
                                WKScriptMessageHandler, WKDownloadDelegate {

  static let home = URL(string: "https://madeed-clinic.web.app/")!
  static let bound: Set<String> = ["madeed-clinic.web.app", "madeed-clinic.firebaseapp.com"]

  private var web: WKWebView!
  private var popup: WKWebView?
  private var popupVC: UIViewController?
  private var downloads: [WKDownload: URL] = [:]
  private let bg = UIColor(red: 0.165, green: 0.71, blue: 0.627, alpha: 1)

  // print() في الصفحة وفي النوافذ التي تفتحها يصل إلى هنا، و close() لنافذة
  // الإيصال لا يغلقها قبل أن يُطبع (openPrintWindow يغلقها بعد ثانيتين).
  private static let printShim = """
  (function(){
    var h = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.abuPrint;
    if(!h) return;
    var post = function(){ h.postMessage(''); };
    window.print = post;
    var open0 = window.open;
    window.open = function(u){
      var w = open0.apply(window, arguments);
      if(w && (!u || u === 'about:blank')){ try{ w.print = post; w.close = function(){}; }catch(e){} }
      return w;
    };
  })();
  """

  override func loadView() {
    let cfg = WKWebViewConfiguration()
    cfg.limitsNavigationsToAppBoundDomains = true
    cfg.websiteDataStore = .default()
    cfg.allowsInlineMediaPlayback = true
    cfg.preferences.javaScriptCanOpenWindowsAutomatically = true
    cfg.userContentController.add(self, name: "abuPrint")
    cfg.userContentController.addUserScript(
      WKUserScript(source: Self.printShim, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
    web = WKWebView(frame: .zero, configuration: cfg)
    web.navigationDelegate = self
    web.uiDelegate = self
    web.isOpaque = false
    web.backgroundColor = bg
    web.scrollView.backgroundColor = bg
    web.allowsBackForwardNavigationGestures = false
    // الصفحة تُحسب ارتفاعها بـ 100vh: نحصر الـ WebView داخل المنطقة الآمنة (بين شريط الحالة
    // ومؤشر الرجوع) كي لا يختبئ الشريط السفلي تحتها، ونمنع الإزاحة التلقائية للمحتوى.
    web.scrollView.contentInsetAdjustmentBehavior = .never
    let root = UIView()
    root.backgroundColor = bg
    web.translatesAutoresizingMaskIntoConstraints = false
    root.addSubview(web)
    let g = root.safeAreaLayoutGuide
    NSLayoutConstraint.activate([
      web.topAnchor.constraint(equalTo: g.topAnchor),
      web.bottomAnchor.constraint(equalTo: g.bottomAnchor),
      web.leadingAnchor.constraint(equalTo: g.leadingAnchor),
      web.trailingAnchor.constraint(equalTo: g.trailingAnchor)
    ])
    view = root
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    web.load(URLRequest(url: Self.home))
  }

  // ---------------------------------------------------------------- التنقّل
  private func isBound(_ url: URL) -> Bool {
    guard let s = url.scheme?.lowercased(), s == "https", let h = url.host?.lowercased() else { return false }
    return Self.bound.contains(h)
  }

  private func openOutside(_ url: URL) {
    UIApplication.shared.open(url, options: [:], completionHandler: nil)
  }

  func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
               decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
    if action.shouldPerformDownload { decisionHandler(.download); return }
    guard let url = action.request.url, let scheme = url.scheme?.lowercased() else { decisionHandler(.allow); return }
    if ["about", "blob", "data"].contains(scheme) || isBound(url) { decisionHandler(.allow); return }
    // إطارات داخلية (Firebase) تبقى؛ أمّا الانتقال بالصفحة كلها إلى خارجها فيُفتح خارج التطبيق
    if action.targetFrame?.isMainFrame ?? true {
      openOutside(url)
      decisionHandler(.cancel)
    } else {
      decisionHandler(.allow)
    }
  }

  func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse,
               decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
    decisionHandler(response.canShowMIMEType ? .allow : .download)
  }

  // الصفحة سقطت (ذاكرة الآيفون): تُعاد بدل شاشة بيضاء
  func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
    webView.reload()
  }

  // ---------------------------------------------------------------- النوافذ
  func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
               for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
    if let url = action.request.url, let s = url.scheme?.lowercased(), s != "about", !url.absoluteString.isEmpty {
      if isBound(url) { web.load(action.request) } else { openOutside(url) }
      return nil
    }
    // نافذة فارغة تكتب فيها الصفحة (الإيصال، الوصفة، خطة العلاج للطباعة)
    let w = WKWebView(frame: .zero, configuration: configuration)
    w.uiDelegate = self
    w.navigationDelegate = self
    let vc = UIViewController()
    vc.view = w
    vc.navigationItem.leftBarButtonItem = UIBarButtonItem(title: "إغلاق", style: .done, target: self,
                                                          action: #selector(closePopup))
    vc.navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .action, target: self,
                                                           action: #selector(printPopup))
    let nav = UINavigationController(rootViewController: vc)
    nav.modalPresentationStyle = .pageSheet
    popup = w
    popupVC = nav
    present(nav, animated: true)
    return w
  }

  func webViewDidClose(_ webView: WKWebView) {
    if webView === popup { closePopup() }
  }

  @objc private func closePopup() {
    popupVC?.dismiss(animated: true)
    popupVC = nil
    popup = nil
  }

  @objc private func printPopup() { printView(popup ?? web) }

  // ---------------------------------------------------------------- الطباعة
  func userContentController(_ uc: WKUserContentController, didReceive message: WKScriptMessage) {
    guard message.name == "abuPrint" else { return }
    // الإيصال يُكتب في النافذة ثم يُطلب طبعه بعد نصف ثانية: نمهله حتى تكتمل الصور
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
      guard let self = self else { return }
      self.printView(self.popup ?? self.web)
    }
  }

  private func printView(_ v: WKWebView) {
    let pc = UIPrintInteractionController.shared
    let info = UIPrintInfo(dictionary: nil)
    info.outputType = .general
    info.jobName = "AbuAzz"
    pc.printInfo = info
    pc.printFormatter = v.viewPrintFormatter()
    pc.present(animated: true, completionHandler: nil)
  }

  // ---------------------------------------------------------------- الرسائل
  func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
               initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
    let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
    a.addAction(UIAlertAction(title: "حسناً", style: .default) { _ in completionHandler() })
    topVC().present(a, animated: true)
  }

  func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
               initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
    let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
    a.addAction(UIAlertAction(title: "إلغاء", style: .cancel) { _ in completionHandler(false) })
    a.addAction(UIAlertAction(title: "موافق", style: .default) { _ in completionHandler(true) })
    topVC().present(a, animated: true)
  }

  func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String,
               defaultText: String?, initiatedByFrame frame: WKFrameInfo,
               completionHandler: @escaping (String?) -> Void) {
    let a = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
    a.addTextField { $0.text = defaultText }
    a.addAction(UIAlertAction(title: "إلغاء", style: .cancel) { _ in completionHandler(nil) })
    a.addAction(UIAlertAction(title: "موافق", style: .default) { _ in completionHandler(a.textFields?.first?.text) })
    topVC().present(a, animated: true)
  }

  private func topVC() -> UIViewController {
    var v: UIViewController = self
    while let p = v.presentedViewController { v = p }
    return v
  }

  // ---------------------------------------------------------------- التنزيلات
  func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
    download.delegate = self
  }

  func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
    download.delegate = self
  }

  func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
                suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let dest = dir.appendingPathComponent(suggestedFilename.isEmpty ? "AbuAzz-file" : suggestedFilename)
    downloads[download] = dest
    completionHandler(dest)
  }

  func downloadDidFinish(_ download: WKDownload) {
    guard let url = downloads.removeValue(forKey: download) else { return }
    let share = UIActivityViewController(activityItems: [url], applicationActivities: nil)
    share.popoverPresentationController?.sourceView = view
    share.popoverPresentationController?.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
    topVC().present(share, animated: true)
  }

  func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
    downloads.removeValue(forKey: download)
  }
}
