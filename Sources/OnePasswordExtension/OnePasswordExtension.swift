import Foundation
import MobileCoreServices
import UIKit

#if canImport(WebKit)
import WebKit
#endif


@objcMembers
public final class OnePasswordExtension: NSObject {
	// MARK: - Login Dictionary keys - Used to get or set the properties of a 1Password Login
	public static let AppExtensionURLStringKey = "url_string"
	public static let AppExtensionUsernameKey = "username"
	public static let AppExtensionPasswordKey = "password"
	public static let AppExtensionTOTPKey = "totp"
	public static let AppExtensionTitleKey = "login_title"
	public static let AppExtensionNotesKey = "notes"
	public static let AppExtensionSectionTitleKey = "section_title"
	public static let AppExtensionFieldsKey = "fields"
	public static let AppExtensionReturnedFieldsKey = "returned_fields"
	public static let AppExtensionOldPasswordKey = "old_password"
	public static let AppExtensionPasswordGeneratorOptionsKey = "password_generator_options"
	
	// Password Generator options - Used to set the 1Password Password Generator options when saving a new Login or when changing the password for for an existing Login
	public static let AppExtensionGeneratedPasswordMinLengthKey = "password_min_length"
	public static let AppExtensionGeneratedPasswordMaxLengthKey = "password_max_length"
	public static let AppExtensionGeneratedPasswordRequireDigitsKey = "password_require_digits"
	public static let AppExtensionGeneratedPasswordRequireSymbolsKey = "password_require_symbols"
	public static let AppExtensionGeneratedPasswordForbiddenCharactersKey = "password_forbidden_characters"
	
	// MARK: - Error Codes
	public static let AppExtensionErrorDomain = "OnePasswordExtension"
	
	public enum AppExtensionErrorCode : Int {
		case cancelledByUser = 0
		case apiNotAvailable = 1
		case failedToContactExtension = 2
		case failedToLoadItemProviderData = 3
		case collectFieldsScriptFailed = 4
		case fillFieldsScriptFailed = 5
		case unexpectedData = 6
		case failedToObtainURLStringFromWebView = 7
	}
	
	//version
	let VERSION_NUMBER = 185
	private let AppExtensionVersionNumberKey = "version_number"
	
	// Available App Extension Actions
	private let kUTTypeAppExtensionFindLoginAction = "org.appextension.find-login-action"
	private let kUTTypeAppExtensionSaveLoginAction = "org.appextension.save-login-action"
	private let kUTTypeAppExtensionChangePasswordAction = "org.appextension.change-password-action"
	private let kUTTypeAppExtensionFillWebViewAction = "org.appextension.fill-webview-action"
	private let kUTTypeAppExtensionFillBrowserAction = "org.appextension.fill-browser-action"
	
	// WebView Dictionary keys
	private let AppExtensionWebViewPageFillScript = "fillScript"
	private let AppExtensionWebViewPageDetails = "pageDetails"
	
	public typealias OnePasswordLoginDictionaryCompletionBlock = (NSDictionary?, NSError?) -> Void
	public typealias OnePasswordSuccessCompletionBlock = (Bool, NSError?) -> Void
	public typealias OnePasswordExtensionItemCompletionBlock = (NSExtensionItem?, NSError?) -> Void
	
	private static let sharedExtension = OnePasswordExtension()
	
	@objc(sharedExtension)
	public static func shared() -> OnePasswordExtension {
		OnePasswordExtension.sharedExtension
	}
	
	private override init() {
		
	}
	
	public func isAppExtensionAvailable() -> Bool {
		if isSystemAppExtensionAPIAvailable() {
			guard let url = URL(string: "org-appextension-feature-password-management://") else {
				return false
			}
			return UIApplication.shared
				.canOpenURL(url)
		}
		
		return false
	}
	
	/*!
	 Called from your login page, this method will find all available logins for the given URLString.
	 
	 @discussion 1Password will show all matching Login for the naked domain of the given URLString. For example if the user has an item in your 1Password vault with "subdomain1.domain.com” as the website and another one with "subdomain2.domain.com”, and the URLString is "https://domain.com", 1Password will show both items.
	 
	 However, if no matching login is found for "https://domain.com", the 1Password Extension will display the "Show all Logins" button so that the user can search among all the Logins in the vault. This is especially useful when the user has a login for "https://olddomain.com".
	 
	 After the user selects a login, it is stored into an NSDictionary and given to your completion handler. Use the `Login Dictionary keys` above to
	 extract the needed information and update your UI. The completion block is guaranteed to be called on the main thread.
	 
	 @param URLString For the matching Logins in the 1Password vault.
	 
	 @param viewController The view controller from which the 1Password Extension is invoked. Usually `self`
	 
	 @param sender The sender which triggers the share sheet to show. UIButton, UIBarButtonItem or UIView. Can also be nil on iPhone, but not on iPad.
	 
	 @param completion A completion block called with two parameters loginDictionary and error once completed. The loginDictionary reply parameter that contains the username, password and the One-Time Password if available. The error Reply parameter that is nil if the 1Password Extension has been successfully completed, or it contains error information about the completion failure.
	 */
	@objc(findLoginForURLString:forViewController:sender:completion:)
	public func findLogin(forURLString URLString: String, for viewController: UIViewController, sender: Any?, completion: OnePasswordLoginDictionaryCompletionBlock? = nil) {
		precondition(URLString.isEmpty == false, "URLString must not be nil")

		guard isSystemAppExtensionAPIAvailable() else {
			NSLog("Failed to findLoginForURLString, system API is not available")
			completion?(nil, OnePasswordExtension.systemAppExtensionAPINotAvailableError())
			return
		}

		let item: NSDictionary = [AppExtensionVersionNumberKey: VERSION_NUMBER, OnePasswordExtension.AppExtensionURLStringKey: URLString]

		guard let activityViewController = self.activityViewController(forItem: item, viewController: viewController, sender: sender, typeIdentifier: kUTTypeAppExtensionFindLoginAction) else {
			NSLog("Failed to get activityViewController")
			completion?(nil, OnePasswordExtension.extensionCancelledByUserError())
			return
		}
		
		activityViewController.completionWithItemsHandler = { activityType, completed, returnedItems, activityError in
			guard let returnedItems = returnedItems, returnedItems.isEmpty == false else {
				let error: NSError
				if let activityError = activityError as NSError? {
					NSLog("Failed to storeLoginForURLString: \(activityError)")
					error = OnePasswordExtension.failedToContactExtensionErrorWithActivityError(activityError: activityError)
				} else {
					error = OnePasswordExtension.extensionCancelledByUserError()
				}
				
				completion?(nil, error)
				return
			}
			
			self.processExtensionItem(returnedItems.first as? NSExtensionItem) { (itemDictionary, error) in
				completion?(itemDictionary, error)
			}
			
		}
		
		viewController.present(activityViewController, animated: true, completion: nil)
	}
	
	// MARK: - New User Registration
	
	/*!
	 Create a new login within 1Password and allow the user to generate a new password before saving.
	 
	 @discussion The provided URLString should be unique to your app or service and be identical to what you pass into the find login method.
	 The completion block is guaranteed to be called on the main
	 thread.
	 
	 @param URLString For the new Login to be saved in 1Password.
	 
	 @param loginDetailsDictionary about the Login to be saved, including custom fields, are stored in an dictionary and given to the 1Password Extension.
	 
	 @param passwordGenerationOptions The Password generator options represented in a dictionary form.
	 
	 @param viewController The view controller from which the 1Password Extension is invoked. Usually `self`
	 
	 @param sender The sender which triggers the share sheet to show. UIButton, UIBarButtonItem or UIView. Can also be nil on iPhone, but not on iPad.
	 
	 @param completion A completion block which is called with type parameters loginDictionary and error. The loginDictionary reply parameter which contain all the information about the newly saved Login. Use the `Login Dictionary keys` above to extract the needed information and update your UI. For example, updating the UI with the newly generated password lets the user know their action was successful. The error reply parameter that is nil if the 1Password Extension has been successfully completed, or it contains error information about the completion failure.
	 */
	public func storeLogin(forURLString URLString: String, loginDetails loginDetailsDictionary: [AnyHashable : Any], passwordGenerationOptions: [AnyHashable : Any]?, for viewController: UIViewController, sender: Any?, completion: OnePasswordLoginDictionaryCompletionBlock? = nil) {
		
		guard isSystemAppExtensionAPIAvailable() else {
			NSLog("Failed to changePasswordForLoginWithUsername, system API is not available")
			completion?(nil, OnePasswordExtension.systemAppExtensionAPINotAvailableError())
			return
		}
		
		let newLoginAttributesDict = NSMutableDictionary()
		newLoginAttributesDict[AppExtensionVersionNumberKey] = VERSION_NUMBER
		newLoginAttributesDict[OnePasswordExtension.AppExtensionURLStringKey] = URLString
		newLoginAttributesDict.addEntries(from: loginDetailsDictionary)
		
		if let passwordGenerationOptions = passwordGenerationOptions, passwordGenerationOptions.isEmpty == false {
			newLoginAttributesDict[OnePasswordExtension.AppExtensionPasswordGeneratorOptionsKey] = passwordGenerationOptions
		}
		
		guard let activityViewController = self.activityViewController(forItem: newLoginAttributesDict, viewController: viewController, sender: sender, typeIdentifier: kUTTypeAppExtensionSaveLoginAction) else {
			NSLog("Failed to get activityViewController")
			completion?(nil, OnePasswordExtension.extensionCancelledByUserError())
			return
		}
		
		activityViewController.completionWithItemsHandler = { activityType, completed, returnedItems, activityError in
			guard let returnedItems = returnedItems, returnedItems.isEmpty == false else {
				let error: NSError
				if let activityError = activityError as NSError? {
					NSLog("Failed to storeLoginForURLString: \(activityError)")
					error = OnePasswordExtension.failedToContactExtensionErrorWithActivityError(activityError: activityError)
				} else {
					error = OnePasswordExtension.extensionCancelledByUserError()
				}
				
				completion?(nil, error)
				return
			}
			
			self.processExtensionItem(returnedItems.first as? NSExtensionItem) { (itemDictionary, error) in
				completion?(itemDictionary, error)
			}
			
		}
		
		viewController.present(activityViewController, animated: true, completion: nil)
	}
	
	// MARK: - Change Password
	
	/*!
	 Change the password for an existing login within 1Password.
	 
	 @discussion The provided URLString should be unique to your app or service and be identical to what you pass into the find login method. The completion block is guaranteed to be called on the main thread.
	 
	 1Password 6 and later:
	 The 1Password Extension will display all available the matching Logins for the given URL string. The user can choose which Login item to update. The "New Login" button will also be available at all times, in case the user wishes to to create a new Login instead,
	 
	 1Password 5:
	 These are the three scenarios that are supported:
	 1. A single matching Login is found: 1Password will enter edit mode for that Login and will update its password using the value for AppExtensionPasswordKey.
	 2. More than a one matching Logins are found: 1Password will display a list of all matching Logins. The user must choose which one to update. Once in edit mode, the Login will be updated with the new password.
	 3. No matching login is found: 1Password will create a new Login using the optional fields if available to populate its properties.
	 
	 @param URLString for the Login to be updated with a new password in 1Password.
	 
	 @param loginDetailsDictionary about the Login to be saved, including old password and the username, are stored in an dictionary and given to the 1Password Extension.
	 
	 @param passwordGenerationOptions The Password generator options epresented in a dictionary form.
	 
	 @param viewController The view controller from which the 1Password Extension is invoked. Usually `self`
	 
	 @param sender The sender which triggers the share sheet to show. UIButton, UIBarButtonItem or UIView. Can also be nil on iPhone, but not on iPad.
	 
	 @param completion A completion block which is called with type parameters loginDictionary and error. The loginDictionary reply parameter which contain all the information about the newly updated Login, including the newly generated and the old password. Use the `Login Dictionary keys` above to extract the needed information and update your UI. For example, updating the UI with the newly generated password lets the user know their action was successful. The error reply parameter that is nil if the 1Password Extension has been successfully completed, or it contains error information about the completion failure.
	 */
	public func changePasswordForLogin(forURLString URLString: String, loginDetails loginDetailsDictionary: [AnyHashable : Any], passwordGenerationOptions: [AnyHashable : Any]?, for viewController: UIViewController, sender: Any?, completion: OnePasswordLoginDictionaryCompletionBlock? = nil) {
		
		guard isSystemAppExtensionAPIAvailable() else {
			NSLog("Failed to changePasswordForLoginWithUsername, system API is not available")
			completion?(nil, OnePasswordExtension.systemAppExtensionAPINotAvailableError())
			return
		}
		
		let item = NSMutableDictionary()
		item[AppExtensionVersionNumberKey] = VERSION_NUMBER
		item[OnePasswordExtension.AppExtensionURLStringKey] = URLString
		item.addEntries(from: loginDetailsDictionary)
		
		if let passwordGenerationOptions = passwordGenerationOptions, passwordGenerationOptions.isEmpty == false {
			item[OnePasswordExtension.AppExtensionPasswordGeneratorOptionsKey] = passwordGenerationOptions
		}
		
		guard let activityViewController = self.activityViewController(forItem: item, viewController: viewController, sender: sender, typeIdentifier: kUTTypeAppExtensionChangePasswordAction) else {
			NSLog("Failed to get activityViewController")
			completion?(nil, OnePasswordExtension.extensionCancelledByUserError())
			return
		}
		
		activityViewController.completionWithItemsHandler = { activityType, completed, returnedItems, activityError in
			guard let returnedItems = returnedItems, returnedItems.isEmpty == false else {
				let error: NSError
				if let activityError = activityError as NSError? {
					NSLog("Failed to changePasswordForLoginWithUsername: \(activityError)")
					error = OnePasswordExtension.failedToContactExtensionErrorWithActivityError(activityError: activityError)
				} else {
					error = OnePasswordExtension.extensionCancelledByUserError()
				}
				
				completion?(nil, error)
				return
			}
			
			self.processExtensionItem(returnedItems.first as? NSExtensionItem) { (itemDictionary, error) in
				completion?(itemDictionary, error)
			}
			
		}
		
		viewController.present(activityViewController, animated: true, completion: nil)
	}
	
	// MARK: - Web View filling Support

	/*!
	 Called from your web view controller, this method will show all the saved logins for the active page in the provided web
	 view, and automatically fill the HTML form fields. Supports WKWebView.
	 
	 @discussion 1Password will show all matching Login for the naked domain of the current website. For example if the user has an item in your 1Password vault with "subdomain1.domain.com” as the website and another one with "subdomain2.domain.com”, and the current website is "https://domain.com", 1Password will show both items.
	 
	 However, if no matching login is found for "https://domain.com", the 1Password Extension will display the "New Login" button so that the user can create a new Login for the current website.
	 
	 @param webView The web view which displays the form to be filled. The active WKWebView. Must not be nil.
	 
	 @param viewController The view controller from which the 1Password Extension is invoked. Usually `self`
	 
	 @param sender The sender which triggers the share sheet to show. UIButton, UIBarButtonItem or UIView. Can also be nil on iPhone, but not on iPad.
	 
	 @param yesOrNo Boolean flag. If YES is passed only matching Login items will be shown, otherwise the 1Password Extension will also display Credit Cards and Identities.
	 
	 @param completion Completion block called on completion with parameters success, and error. The success reply parameter that is YES if the 1Password Extension has been successfully completed or NO otherwise. The error reply parameter that is nil if the 1Password Extension has been successfully completed, or it contains error information about the completion failure.
	 */
	public func fillItem(into webView: WKWebView, for viewController: UIViewController, sender: Any?, showOnlyLogins yesOrNo: Bool, completion: @escaping OnePasswordSuccessCompletionBlock) {
		fillItemWK(into: webView, for: viewController, sender: sender, showOnlyLogins: yesOrNo, completion: completion)
	}
	
	// MARK: - Support for custom UIActivityViewControllers
	
	/*!
	 Called in the UIActivityViewController completion block to find out whether or not the user selected the 1Password Extension activity.
	 
	 @param activityType or the bundle identidier of the selected activity in the share sheet.
	 
	 @return isOnePasswordExtensionActivityType Returns YES if the selected activity is the 1Password extension, NO otherwise.
	 */
	public func isOnePasswordExtension(activityType: String) -> Bool {
		"com.agilebits.onepassword-ios.extension" == activityType ||
			"com.agilebits.beta.onepassword-ios.extension" == activityType
	}
	
	/*!
	 The returned NSExtensionItem can be used to create your own UIActivityViewController. Use `isOnePasswordExtensionActivityType:` and `fillReturnedItems:intoWebView:completion:` in the activity view controller completion block to process the result. The completion block is guaranteed to be called on the main thread.
	 
	 @param webView The web view which displays the form to be filled. The active WKWebView. Must not be nil.
	 
	 @param completion Completion block called on completion with extensionItem and error. The extensionItem reply parameter that is contains all the info required by the 1Password extension if has been successfully completed or nil otherwise. The error reply parameter that is nil if the 1Password extension item has been successfully created, or it contains error information about the completion failure.
	 */
	public func createExtensionItem(for webview: WKWebView, completion: OnePasswordExtensionItemCompletionBlock? = nil) {
		
		let safeCompletion = { (completionError: NSError) in
			if let completion = completion {
				if Thread.isMainThread {
					completion(nil, completionError)
				} else {
					OperationQueue.main.addOperation {
						completion(nil, completionError)
					}
				}
			}
		}
		
		webview.evaluateJavaScript(OnePasswordExtension.OPWebViewCollectFieldsScript) { (result, evaluateError) in
			guard let result = result,
						let urlStringResult = result as? String,
						let webViewURL = webview.url?.absoluteString
			else {
				let completionError: NSError = (evaluateError as NSError?) ?? NSError(domain: OnePasswordExtension.AppExtensionErrorDomain, code: 0)
				NSLog("1Password Extension failed to collect web page fields: \(completionError)")
				let failedToCollectFieldsError = OnePasswordExtension.failedToCollectFieldsErrorWithUnderlyingError(underlyingError: completionError)
				safeCompletion(failedToCollectFieldsError)
				return
			}
			
			self.createExtensionItem(forURLString: webViewURL,
													webPageDetails: urlStringResult,
													completion: completion)
		}
	}
	
	/*!
	 Method used in the UIActivityViewController completion block to fill information into a web view.
	 
	 @param returnedItems Array which contains the selected activity in the share sheet. Empty array if the share sheet is cancelled by the user.
	 @param webView The web view which displays the form to be filled. The active WKWebView. Must not be nil.
	 
	 @param completion Completion block called on completion with parameters success, and error. The success reply parameter that is YES if the 1Password Extension has been successfully completed or NO otherwise. The error reply parameter that is nil if the 1Password Extension has been successfully completed, or it contains error information about the completion failure.
	 */
	public func fill(returnedItems: NSArray, into webView: WKWebView, completion: OnePasswordSuccessCompletionBlock? = nil) {
		guard returnedItems.count > 0 else {
			let error = OnePasswordExtension.extensionCancelledByUserError()
			completion?(false, error)
			return
		}
		
		processExtensionItem(returnedItems.firstObject as? NSExtensionItem) { (itemDictionary, error) in
			guard let itemDictionary = itemDictionary, itemDictionary.count > 0,
						let fillScript = itemDictionary[self.AppExtensionWebViewPageFillScript] as? String
			else {
				completion?(false, error)
				return
			}
			
			self.executeFillScript(fillScript, in: webView) { (success, executeFillScriptError) in
				completion?(success, executeFillScriptError)
			}
		}
	}
	
	// MARK: - Private methods
	
	private func isSystemAppExtensionAPIAvailable() -> Bool {
		// This is always true in swift
		return true //NSExtensionItem.self != nil
	}
	
	private func findLoginIn1Password(withURLString URLString: String, collectedPageDetails: String?, forWebViewController forViewController: UIViewController, sender: Any?, with webView: WKWebView, showOnlyLogins yesOrNo: Bool, completion: @escaping OnePasswordSuccessCompletionBlock) {
		
		guard URLString.isEmpty == false,
					let data = collectedPageDetails?.data(using: .utf8) else {
			let urlStringError = OnePasswordExtension.failedToObtainURLStringFromWebViewError()
			NSLog("Failed to findLoginIn1PasswordWithURLString: \(urlStringError)")
			completion(false, urlStringError)
			return
		}
		
		let collectedPageDetailsDictionary: NSDictionary
		do {
			let collectedPageDetails = try JSONSerialization.jsonObject(with: data, options: .mutableContainers) as? NSDictionary
			
			guard let collectedPageDetailsDictionaryTemp = collectedPageDetails else {
				throw NSError(domain: OnePasswordExtension.AppExtensionErrorDomain, code: AppExtensionErrorCode.unexpectedData.rawValue, userInfo: [NSLocalizedDescriptionKey : "Failed to parse JSON collected page details."])
			}
			
			collectedPageDetailsDictionary = collectedPageDetailsDictionaryTemp
		} catch let error as NSError {
			NSLog("Failed to parse JSON collected page details: \(error)")
			completion(false, error)
			return
		}
		
		let item: NSDictionary = [ AppExtensionVersionNumberKey : VERSION_NUMBER,
															 OnePasswordExtension.AppExtensionURLStringKey : URLString,
																		 AppExtensionWebViewPageDetails : collectedPageDetailsDictionary]
		
		let typeIdentifier = yesOrNo ? kUTTypeAppExtensionFillWebViewAction  : kUTTypeAppExtensionFillBrowserAction
		guard let activityViewController =
			self.activityViewController(forItem: item,
																	viewController: forViewController,
																	sender: sender,
																	typeIdentifier: typeIdentifier) else {
			completion(false, OnePasswordExtension.extensionCancelledByUserError())
			return
		}
		
		activityViewController.completionWithItemsHandler = { [weak self] activityType, completed, returnedItems, activityError in
			guard let self = self, returnedItems?.isEmpty == false else {
				guard let activityError = activityError as NSError? else {
					completion(false, OnePasswordExtension.extensionCancelledByUserError())
					return
				}
				
				completion(false, OnePasswordExtension.failedToContactExtensionErrorWithActivityError(activityError: activityError))
				return
			}
			
			self.processExtensionItem(returnedItems?.first as? NSExtensionItem) { (itemDictionary, processExtensionItemError) in
				guard let itemDictionary = itemDictionary, itemDictionary.count > 0 else {
					completion(false, processExtensionItemError)
					return
				}
				
				let fillScript = itemDictionary[self.AppExtensionWebViewPageFillScript] as? String
				self.executeFillScript(fillScript, in: webView) { (succes, executeFillScriptError) in
					completion(succes, executeFillScriptError)
				}
				
			}
			
			
		}
		
		forViewController.present(activityViewController, animated: true)
	}

	private func fillItemWK(into webView: WKWebView, for viewController: UIViewController, sender: Any?, showOnlyLogins yesOrNo: Bool, completion: @escaping OnePasswordSuccessCompletionBlock) {
		webView.evaluateJavaScript(OnePasswordExtension.OPWebViewCollectFieldsScript) { (result, error) in
			guard let result = result as? String,
						let webKitURL = webView.url?.absoluteString else {
				let completionError = (error as NSError?) ?? NSError(domain: OnePasswordExtension.AppExtensionErrorDomain, code: AppExtensionErrorCode.collectFieldsScriptFailed.rawValue, userInfo: nil)
				completion(false,
									 OnePasswordExtension.failedToCollectFieldsErrorWithUnderlyingError(underlyingError: completionError))
				return
			}
			
			self.findLoginIn1Password(withURLString: webKitURL, collectedPageDetails: result, forWebViewController: viewController, sender: sender, with: webView, showOnlyLogins: yesOrNo) { (success, findLoginError) in
				completion(success, findLoginError)
			}
		}
	}

	private func executeFillScript(_ fillScript: String?, in webView: WKWebView, completion: @escaping OnePasswordSuccessCompletionBlock) {
		
		guard let fillScript = fillScript else {
			NSLog("Failed to executeFillScript, fillScript is missing")
			completion(false, OnePasswordExtension.failedToFillFieldsErrorWithLocalizedErrorMessage(errorMessage: NSLocalizedString("Failed to fill web page because script is missing", tableName: "OnePasswordExtension", comment: "1Password Extension Error Message"), underlyingError: nil))
			return
		}
		
		let scriptSource = OnePasswordExtension.OPWebViewFillScript
			.appendingFormat("(document, %@, undefined);", fillScript)

		webView.evaluateJavaScript(scriptSource) { (result, evaluationError) in
			var error = evaluationError as NSError?
			let success = result != nil
			
			if success == false {
				NSLog("Cannot executeFillScript, evaluateJavaScript failed: \(String(describing: evaluationError))")
				error = OnePasswordExtension.failedToFillFieldsErrorWithLocalizedErrorMessage(errorMessage: NSLocalizedString("Failed to fill web page because script could not be evaluated", tableName: "OnePasswordExtension", comment: "1Password Extension Error Message"), underlyingError: evaluationError as NSError?)
			}
			
			completion(success, error)
		}
	}

	private func processExtensionItem(_ extensionItem: NSExtensionItem?, completion: @escaping OnePasswordLoginDictionaryCompletionBlock) {
		guard let extensionItem = extensionItem, extensionItem.attachments?.isEmpty == false else {
			let userInfo = [ NSLocalizedDescriptionKey : "Unexpected data returned by App Extension: extension item had no attachments." ]
			let error = NSError(domain: OnePasswordExtension.AppExtensionErrorDomain, code: AppExtensionErrorCode.unexpectedData.rawValue, userInfo: userInfo)
			completion(nil, error)
			return
		}
		
		let itemProvider = extensionItem.attachments?.first
		guard itemProvider?.hasItemConformingToTypeIdentifier(kUTTypePropertyList as String) != nil else {
			let userInfo = [ NSLocalizedDescriptionKey: "Unexpected data returned by App Extension: extension item attachment does not conform to kUTTypePropertyList type identifier" ]
			let error = NSError(domain: OnePasswordExtension.AppExtensionErrorDomain, code: AppExtensionErrorCode.unexpectedData.rawValue, userInfo: userInfo)
			completion(nil, error)
			return
		}
		
		itemProvider?.loadItem(forTypeIdentifier: kUTTypePropertyList as String, options: nil, completionHandler: { (itemDictionaryEncoded, itemProviderError) in
			var error: NSError?
			
			guard let itemDictionary = itemDictionaryEncoded as? NSDictionary,
						itemDictionary.count > 0 else {
				NSLog("Failed to loadItemForTypeIdentifier: \(String(describing: itemProviderError))")
				error = OnePasswordExtension.failedToLoadItemProviderDataErrorWithUnderlyingError(underlyingError: itemProviderError as NSError?)
				return
			}
			
			if Thread.isMainThread {
				completion(itemDictionary, error)
			} else {
				DispatchQueue.main.async {
					completion(itemDictionary, error)
				}
			}
			
		})
	}

	private func activityViewController(forItem item: NSDictionary, viewController: UIViewController, sender: Any?, typeIdentifier: String) -> UIActivityViewController? {
		precondition(false == (UIDevice.current.userInterfaceIdiom == .pad && sender == nil), "sender must not be nil on iPad.")
		
		let itemProvider = NSItemProvider(item: item, typeIdentifier: typeIdentifier)
		let extensionItem  = NSExtensionItem()
		extensionItem.attachments = [itemProvider]
		
		let controller = UIActivityViewController(activityItems: [extensionItem], applicationActivities: nil)
		
		if let barbuttonItem = sender as? UIBarButtonItem {
			controller.popoverPresentationController?.barButtonItem = barbuttonItem
		} else if let view = sender as? UIView {
			controller.popoverPresentationController?.sourceView = view.superview
			controller.popoverPresentationController?.sourceRect = view.frame
		} else {
			NSLog("sender can be nil on iPhone")
		}
		
		return controller
	}
	
	private func createExtensionItem(forURLString urlString: String, webPageDetails: String, completion: OnePasswordExtensionItemCompletionBlock? = nil) {
		
		guard let data = webPageDetails.data(using: .utf8) else {
			NSLog("Failed to parse JSON collected page details")
			let error = NSError(domain: OnePasswordExtension.AppExtensionErrorDomain, code: AppExtensionErrorCode.unexpectedData.rawValue, userInfo: [NSLocalizedDescriptionKey : "Failed to get data"])
			completion?(nil, error)
			return
		}
		
		let webPageDetailsDictionary: NSDictionary
		do {
			let webPageDetails = try JSONSerialization.jsonObject(with: data, options: .mutableContainers)
			
			guard let webPageDetailsDictionaryTemp = webPageDetails as? NSDictionary else {
				let error = NSError(domain: OnePasswordExtension.AppExtensionErrorDomain, code: AppExtensionErrorCode.unexpectedData.rawValue, userInfo: [NSLocalizedDescriptionKey : "Failed to get data"])
				throw error
			}
			
			webPageDetailsDictionary = webPageDetailsDictionaryTemp
		} catch let error as NSError {
			NSLog("Failed to parse JSON collected page details: \(String(describing: error))")
			completion?(nil, error)
			return
		}
		
		let item: NSDictionary = [AppExtensionVersionNumberKey : VERSION_NUMBER, OnePasswordExtension.AppExtensionURLStringKey : urlString, AppExtensionWebViewPageDetails : webPageDetailsDictionary]
		
		let itemProvider = NSItemProvider(item: item, typeIdentifier: kUTTypeAppExtensionFillBrowserAction)
		let extensionItem = NSExtensionItem()
		extensionItem.attachments = [itemProvider]
		
		if Thread.isMainThread {
			completion?(extensionItem, nil)
		} else {
			DispatchQueue.main.async {
				completion?(extensionItem, nil)
			}
		}
	}
	
	// MARK: - Errors
	
	private static func systemAppExtensionAPINotAvailableError() -> NSError {
		NSError(domain: AppExtensionErrorDomain,
						code: AppExtensionErrorCode.apiNotAvailable.rawValue,
						userInfo: [NSLocalizedDescriptionKey
												: NSLocalizedString("App Extension API is not available in this version of iOS",
																						tableName: "OnePasswordExtension",
																						comment: "1Password Extension Error Message")])
	}
	
	private static func extensionCancelledByUserError() -> NSError {
		NSError(domain: AppExtensionErrorDomain,
						code: AppExtensionErrorCode.cancelledByUser.rawValue,
						userInfo: [NSLocalizedDescriptionKey
												: NSLocalizedString("1Password Extension was cancelled by the user",
																						tableName: "OnePasswordExtension",
																						comment: "1Password Extension Error Message")])
	}
	
	private static func failedToContactExtensionErrorWithActivityError(activityError: NSError) -> NSError {
		NSError(domain: AppExtensionErrorDomain,
						code: AppExtensionErrorCode.failedToContactExtension.rawValue,
						userInfo: [NSLocalizedDescriptionKey
												: NSLocalizedString("Failed to contact the 1Password Extension",
																						tableName: "OnePasswordExtension",
																						comment: "1Password Extension Error Message"),
											 NSUnderlyingErrorKey : activityError])
	}
	
	private static func failedToCollectFieldsErrorWithUnderlyingError(underlyingError: NSError) -> NSError {
		NSError(domain: AppExtensionErrorDomain,
						code: AppExtensionErrorCode.collectFieldsScriptFailed.rawValue,
						userInfo: [NSLocalizedDescriptionKey
												: NSLocalizedString("Failed to execute script that collects web page information",
																						tableName: "OnePasswordExtension",
																						comment: "1Password Extension Error Message"),
											 NSUnderlyingErrorKey : underlyingError])
	}
	
	private static func failedToFillFieldsErrorWithLocalizedErrorMessage(errorMessage: String, underlyingError: NSError?) -> NSError {
		NSError(domain: AppExtensionErrorDomain,
						code: AppExtensionErrorCode.fillFieldsScriptFailed.rawValue,
						userInfo: {
							var userInfo: [String: Any] = [
								NSLocalizedDescriptionKey
									: NSLocalizedString("Failed to execute script that collects web page information",
																			tableName: "OnePasswordExtension",
																			comment: "1Password Extension Error Message"),
								NSLocalizedDescriptionKey : errorMessage]
							userInfo[NSUnderlyingErrorKey] = underlyingError
							return userInfo
						}()
		)
	}
	
	private static func failedToLoadItemProviderDataErrorWithUnderlyingError(underlyingError: NSError?) -> NSError {
		NSError(domain: AppExtensionErrorDomain,
						code: AppExtensionErrorCode.failedToLoadItemProviderData.rawValue,
						userInfo: [NSLocalizedDescriptionKey
												: NSLocalizedString("Failed to parse information returned by 1Password Extension",
																						tableName: "OnePasswordExtension",
																						comment: "1Password Extension Error Message"),
											 NSUnderlyingErrorKey : underlyingError as Any])
	}
	
	private static func failedToObtainURLStringFromWebViewError() -> NSError {
		NSError(domain: AppExtensionErrorDomain,
						code: AppExtensionErrorCode.failedToObtainURLStringFromWebView.rawValue,
						userInfo: [NSLocalizedDescriptionKey
												: NSLocalizedString("Failed to obtain URL String from web view. The web view must be loaded completely when calling the 1Password Extension",
																						tableName: "OnePasswordExtension",
																						comment: "1Password Extension Error Message")
						])
	}
	
	private static let OPWebViewCollectFieldsScript = """
	";(function(document, undefined) {\
	\
		document.addEventListener('input',function(b){!1!==b.isTrusted&&'input'===b.target.tagName.toLowerCase()&&(b.target.dataset['com.agilebits.onepassword.userEdited']='yes')},!0);\
	(function(b,a,c){a.FieldCollector=new function(){function f(d){return d?d.toString().toLowerCase():''}function e(d,b,a,e){e!==c&&e===a||null===a||a===c||(d[b]=a)}function k(d,b){var a=[];try{a=d.querySelectorAll(b)}catch(J){console.error('[COLLECT FIELDS] @ag_querySelectorAll Exception in selector \"'+b+'\"')}return a}function m(d){var a,c=[];if(d.labels&&d.labels.length&&0<d.labels.length)c=Array.prototype.slice.call(d.labels);else{d.id&&(c=c.concat(Array.prototype.slice.call(k(b,'label[for='+JSON.stringify(d.id)+\
	']'))));if(d.name){a=k(b,'label[for='+JSON.stringify(d.name)+']');for(var e=0;e<a.length;e++)-1===c.indexOf(a[e])&&c.push(a[e])}for(a=d;a&&a!=b;a=a.parentNode)'label'===f(a.tagName)&&-1===c.indexOf(a)&&c.push(a)}0===c.length&&(a=d.parentNode,'dd'===a.tagName.toLowerCase()&&null!==a.previousElementSibling&&'dt'===a.previousElementSibling.tagName.toLowerCase()&&c.push(a.previousElementSibling));return 0<c.length?c.map(function(d){return l(r(d))}).join(''):null}function n(d){var a;for(d=d.parentElement||\
	d.parentNode;d&&'td'!=f(d.tagName);)d=d.parentElement||d.parentNode;if(!d||d===c)return null;a=d.parentElement||d.parentNode;if('tr'!=a.tagName.toLowerCase())return null;a=a.previousElementSibling;if(!a||'tr'!=(a.tagName+'').toLowerCase()||a.cells&&d.cellIndex>=a.cells.length)return null;d=r(a.cells[d.cellIndex]);return d=l(d)}function p(a){return a.options?(a=Array.prototype.slice.call(a.options).map(function(a){var d=a.text,d=d?f(d).replace(/\\s/mg,'').replace(/[~`!@$%^&*()\\-_+=:;'\"\\[\\]|\\\\,<.>\\/?]/mg,\
	''):null;return[d?d:null,a.value]}),{options:a}):null}function F(a){switch(f(a.type)){case 'checkbox':return a.checked?'✓':'';case 'hidden':a=a.value;if(!a||'number'!=typeof a.length)return'';254<a.length&&(a=a.substr(0,254)+'...SNIPPED');return a;case 'submit':case 'button':case 'reset':if(''===a.value)return l(r(a))||'';default:return a.value}}function G(a,b){if(-1===['text','password'].indexOf(b.type.toLowerCase())||!(h.test(a.value)||h.test(a.htmlID)||h.test(a.htmlName)||h.test(a.placeholder)||\
	h.test(a['label-tag'])||h.test(a['label-data'])||h.test(a['label-aria'])))return!1;if(!a.visible)return!0;if('password'==b.type.toLowerCase())return!1;a=b.type;t(b,!0);return a!==b.type}function H(a){var b={};a.forEach(function(a){b[a.opid]=a});return b}function g(a,b){var c=a[b];if('string'==typeof c)return c;a=a.getAttribute(b);return'string'==typeof a?a:null}function z(a){return'input'===a.nodeName.toLowerCase()&&-1===a.type.search(/button|submit|reset|hidden|checkbox/i)}var u={},h=/((\\b|_|-)pin(\\b|_|-)|password|passwort|kennwort|(\\b|_|-)passe(\\b|_|-)|contraseña|senha|密码|adgangskode|hasło|wachtwoord)/i;\
	this.collect=this.a=function(b,c){u={};var d=b.defaultView?b.defaultView:a,h=b.activeElement,E=Array.prototype.slice.call(k(b,'form')).map(function(a,b){var c={};b='__form__'+b;a.opid=b;c.opid=b;e(c,'htmlName',g(a,'name'));e(c,'htmlID',g(a,'id'));b=g(a,'action');b=new URL(b,window.location.href);e(c,'htmlAction',b?b.href:null);e(c,'htmlMethod',g(a,'method'));return c}),D=Array.prototype.slice.call(v(b)).map(function(a,b){z(a)&&a.hasAttribute('value')&&!a.dataset['com.agilebits.onepassword.initialValue']&&\
	(a.dataset['com.agilebits.onepassword.initialValue']=a.value);var c={},d='__'+b,q=-1==a.maxLength?999:a.maxLength;if(!q||'number'===typeof q&&isNaN(q))q=999;u[d]=a;a.opid=d;c.opid=d;c.elementNumber=b;e(c,'maxLength',Math.min(q,999),999);c.visible=w(a);c.viewable=x(a);e(c,'htmlID',g(a,'id'));e(c,'htmlName',g(a,'name'));e(c,'htmlClass',g(a,'class'));e(c,'tabindex',g(a,'tabindex'));e(c,'title',g(a,'title'));e(c,'userEdited',!!a.dataset['com.agilebits.onepassword.userEdited']);if('hidden'!=f(a.type)){e(c,\
	'label-tag',m(a));e(c,'label-data',g(a,'data-label'));e(c,'label-aria',g(a,'aria-label'));e(c,'label-top',n(a));b=[];for(d=a;d&&d.nextSibling;){d=d.nextSibling;if(y(d))break;A(b,d)}e(c,'label-right',b.join(''));b=[];B(a,b);b=b.reverse().join('');e(c,'label-left',b);e(c,'placeholder',g(a,'placeholder'))}e(c,'rel',g(a,'rel'));e(c,'type',f(g(a,'type')));e(c,'value',F(a));e(c,'checked',a.checked,!1);e(c,'autoCompleteType',a.getAttribute('x-autocompletetype')||a.getAttribute('autocompletetype')||a.getAttribute('autocomplete'),\
	'off');e(c,'disabled',a.disabled);e(c,'readonly',a.c||a.readOnly);e(c,'selectInfo',p(a));e(c,'aria-hidden','true'==a.getAttribute('aria-hidden'),!1);e(c,'aria-disabled','true'==a.getAttribute('aria-disabled'),!1);e(c,'aria-haspopup','true'==a.getAttribute('aria-haspopup'),!1);e(c,'data-unmasked',a.dataset.unmasked);e(c,'data-stripe',g(a,'data-stripe'));e(c,'data-braintree-name',g(a,'data-braintree-name'));e(c,'onepasswordFieldType',a.dataset.onepasswordFieldType||a.type);e(c,'onepasswordDesignation',\
	a.dataset.onepasswordDesignation);e(c,'onepasswordSignInUrl',a.dataset.onepasswordSignInUrl);e(c,'onepasswordSectionTitle',a.dataset.onepasswordSectionTitle);e(c,'onepasswordSectionFieldKind',a.dataset.onepasswordSectionFieldKind);e(c,'onepasswordSectionFieldTitle',a.dataset.onepasswordSectionFieldTitle);e(c,'onepasswordSectionFieldValue',a.dataset.onepasswordSectionFieldValue);a.form&&(c.form=g(a.form,'opid'));e(c,'fakeTested',G(c,a),!1);return c});D.filter(function(a){return a.fakeTested}).forEach(function(a){var b=\
	u[a.opid];b.getBoundingClientRect();var c=b.value;t(b,!1);b.dispatchEvent(C(b,'keydown'));b.dispatchEvent(C(b,'keypress'));b.dispatchEvent(C(b,'keyup'));if(''===b.value||b.dataset['com.agilebits.onepassword.initialValue']&&b.value===b.dataset['com.agilebits.onepassword.initialValue'])b.value=c;b.click&&b.click();a.postFakeTestVisible=w(b);a.postFakeTestViewable=x(b);a.postFakeTestType=b.type;a=b.value;var c=b.ownerDocument.createEvent('HTMLEvents'),d=b.ownerDocument.createEvent('HTMLEvents');b.dispatchEvent(C(b,\
	'keydown'));b.dispatchEvent(C(b,'keypress'));b.dispatchEvent(C(b,'keyup'));d.initEvent('input',!0,!0);b.dispatchEvent(d);c.initEvent('change',!0,!0);b.dispatchEvent(c);b.blur();if(''===b.value||b.dataset['com.agilebits.onepassword.initialValue']&&b.value===b.dataset['com.agilebits.onepassword.initialValue'])b.value=a});c={documentUUID:c,title:b.title,url:d.location.href,documentURL:b.location.href,forms:H(E),fields:D,collectedTimestamp:(new Date).getTime()};(b=b.querySelector('[data-onepassword-title]'))&&\
	b.dataset.onepasswordTitle&&(c.displayTitle=b.dataset.onepasswordTitle);h&&z(h)&&t(h,!0);return c};this.elementForOPID=this.b=function(a){return u[a]}}})(document,window,void 0);document.elementForOPID=I;function C(b,a){var c;c=b.ownerDocument.createEvent('Events');c.initEvent(a,!0,!1);c.charCode=0;c.keyCode=0;c.which=0;c.srcElement=b;c.target=b;return c}window.LOGIN_TITLES=[/^\\W*log\\W*[oi]n\\W*$/i,/log\\W*[oi]n (?:securely|now)/i,/^\\W*sign\\W*[oi]n\\W*$/i,'continue','submit','weiter','accès','вход','connexion','entrar','anmelden','accedi','valider','登录','लॉग इन करें'];window.CHANGE_PASSWORD_TITLES=[/^(change|update) password$/i,'save changes','update'];\
	window.LOGIN_RED_HERRING_TITLES=['already have an account','sign in with'];window.REGISTER_TITLES=['register','sign up','signup','join',/^create (my )?(account|profile)$/i,'регистрация','inscription','regístrate','cadastre-se','registrieren','registrazione','注册','साइन अप करें'];window.SEARCH_TITLES='search find поиск найти искать recherche suchen buscar suche ricerca procurar 検索'.split(' ');window.FORGOT_PASSWORD_TITLES='forgot geändert vergessen hilfe changeemail español'.split(' ');\
	window.REMEMBER_ME_TITLES=['remember me','rememberme','keep me signed in'];window.BACK_TITLES=['back','назад'];window.DIVITIS_BUTTON_CLASSES=['button','btn-primary'];function r(b){return b.textContent||b.innerText}function l(b){var a=null;b&&(a=b.replace(/^\\s+|\\s+$|\\r?\\n.*$/mg,'').replace(/\\s{2,}/,' '),a=0<a.length?a:null);return a}function A(b,a){var c='';3===a.nodeType?c=a.nodeValue:1===a.nodeType&&(c=r(a));(a=l(c))&&b.push(a)}\
	function y(b){var a;b&&void 0!==b?(a='select option input form textarea button table iframe body head script'.split(' '),b?(b=b?(b.tagName||'').toLowerCase():'',a=a.constructor==Array?0<=a.indexOf(b):b===a):a=!1):a=!0;return a}\
	function B(b,a,c){var f;for(c||(c=0);b&&b.previousSibling;){b=b.previousSibling;if(y(b))return;A(a,b)}if(b&&0===a.length){for(f=null;!f;){b=b.parentElement||b.parentNode;if(!b)return;for(f=b.previousSibling;f&&!y(f)&&f.lastChild;)f=f.lastChild}y(f)||(A(a,f),0===a.length&&B(f,a,c+1))}}\
	function w(b){for(var a=b,c=(b=b.ownerDocument)?b.defaultView:{},f;a&&a!==b;){f=c.getComputedStyle&&a instanceof Element?c.getComputedStyle(a,null):a.style;if(!f)return!0;if('none'===f.display||'hidden'==f.visibility)return!1;a=a.parentNode}return a===b}\
	function x(b){var a=b.ownerDocument.documentElement,c=b.getBoundingClientRect(),f=a.scrollWidth,e=a.scrollHeight,k=c.left-a.clientLeft,a=c.top-a.clientTop,m;if(!w(b)||!b.offsetParent||10>b.clientWidth||10>b.clientHeight)return!1;var n=b.getClientRects();if(0===n.length)return!1;for(var p=0;p<n.length;p++)if(m=n[p],m.left>f||0>m.right)return!1;if(0>k||k>f||0>a||a>e)return!1;for(c=b.ownerDocument.elementFromPoint(k+(c.right>window.innerWidth?(window.innerWidth-k)/2:c.width/2),a+(c.bottom>window.innerHeight?\
	(window.innerHeight-a)/2:c.height/2));c&&c!==b&&c!==document;){if(c.tagName&&'string'===typeof c.tagName&&'label'===c.tagName.toLowerCase()&&b.labels&&0<b.labels.length)return 0<=Array.prototype.slice.call(b.labels).indexOf(c);c=c.parentNode}return c===b}\
	function I(b){var a;if(void 0===b||null===b)return null;if(a=FieldCollector.b(b))return a;try{var c=Array.prototype.slice.call(v(document)),f=c.filter(function(a){return a.opid==b});if(0<f.length)a=f[0],1<f.length&&console.warn('More than one element found with opid '+b);else{var e=parseInt(b.split('__')[1],10);isNaN(e)||(a=c[e])}}catch(k){console.error('An unexpected error occurred: '+k)}finally{return a}};function v(b){var a=[];try{a=b.querySelectorAll('input, select, button')}catch(c){console.error('[COMMON] @ag_querySelectorAll Exception in selector \"input, select, button\"')}return a}function t(b,a){if(b){var c;a&&(c=b.value);'function'===typeof b.click&&b.click();'function'===typeof b.focus&&b.focus();a&&b.value!==c&&(b.value=c)}};\
		\
		return JSON.stringify(FieldCollector.a(document, 'oneshotUUID'));\
	})(document);\
	\

	"""
	
	static let OPWebViewFillScript = """
 ;(function(document, fillScript, undefined) {\
 \
  var g=!0,h=!0,k=!0;function m(a){return a?0===a.indexOf('https://')&&'http:'===document.location.protocol&&(a=document.querySelectorAll('input[type=password]'),0<a.length&&(confirmResult=confirm('1Password warning: This is an unsecured HTTP page, and any information you submit can potentially be seen and changed by others. This Login was originally saved on a secure (HTTPS) page.\\n\\nDo you still wish to fill this login?'),0==confirmResult))?!0:!1:!1}\
 function l(a){var b,c=[],d=a.properties,e=1,f=[];d&&d.delay_between_operations&&(e=d.delay_between_operations);if(!m(a.savedURL)){var r=function(a,b){var c=a[0];if(void 0===c)b();else{if('delay'===c.operation||'delay'===c[0])e=c.parameters?c.parameters[0]:c[1];else if(c=n(c))for(var d=0;d<c.length;d++)-1===f.indexOf(c[d])&&f.push(c[d]);setTimeout(function(){r(a.slice(1),b)},e)}};g=k=!0;if(b=a.options)b.hasOwnProperty('animate')&&(h=b.animate),b.hasOwnProperty('markFilling')&&(g=b.markFilling);if((b=\
 a.metadata)&&b.hasOwnProperty('action'))switch(b.action){case 'fillPassword':g=!1;break;case 'fillLogin':k=!1}a.hasOwnProperty('script')&&r(a.script,function(){a.hasOwnProperty('autosubmit')&&'function'==typeof autosubmit&&(a.itemType&&'fillLogin'!==a.itemType||(0<f.length?setTimeout(function(){autosubmit(a.autosubmit,d.allow_clicky_autosubmit,f)},AUTOSUBMIT_DELAY):DEBUG_AUTOSUBMIT&&console.log('[AUTOSUBMIT] Not attempting to submit since no fields were filled: ',f)));c=f.map(function(a){return a&&\
 a.hasOwnProperty('opid')?a.opid:null});'object'==typeof protectedGlobalPage&&protectedGlobalPage.c('fillItemResults',{documentUUID:documentUUID,fillContextIdentifier:a.fillContextIdentifier,usedOpids:c},function(){fillingItemType=null})})}}var y={fill_by_opid:p,fill_by_query:q,click_on_opid:t,click_on_query:u,touch_all_fields:v,simple_set_value_by_query:w,focus_by_opid:x,delay:null};\
 function n(a){var b;if(a.hasOwnProperty('operation')&&a.hasOwnProperty('parameters'))b=a.operation,a=a.parameters;else if('[object Array]'===Object.prototype.toString.call(a))b=a[0],a=a.splice(1);else return null;return y.hasOwnProperty(b)?y[b].apply(this,a):null}function p(a,b){return(a=z(a))?(A(a,b),[a]):null}function q(a,b){a=B(a);return Array.prototype.map.call(Array.prototype.slice.call(a),function(a){A(a,b);return a},this)}\
 function w(a,b){var c=[];a=B(a);Array.prototype.forEach.call(Array.prototype.slice.call(a),function(a){a.disabled||a.a||a.readOnly||void 0===a.value||(a.value=b,c.push(a))});return c}function x(a){(a=z(a))&&C(a,!0);return null}function t(a){return(a=z(a))?C(a,!1)?[a]:null:null}function u(a){a=B(a);return Array.prototype.map.call(Array.prototype.slice.call(a),function(a){C(a,!0);return[a]},this)}function v(){D()};var E={'true':!0,y:!0,1:!0,yes:!0,'✓':!0},F=200;function A(a,b){var c;if(!(!a||null===b||void 0===b||k&&(a.disabled||a.a||a.readOnly)))switch(g&&!a.opfilled&&(a.opfilled=!0,a.form&&(a.form.opfilled=!0)),a.type?a.type.toLowerCase():null){case 'checkbox':c=b&&1<=b.length&&E.hasOwnProperty(b.toLowerCase())&&!0===E[b.toLowerCase()];a.checked===c||G(a,function(a){a.checked=c});break;case 'radio':!0===E[b.toLowerCase()]&&a.click();break;default:a.value==b||G(a,function(a){a.value=b})}}\
 function G(a,b){H(a);b(a);I(a);J(a)&&(a.className+=' com-agilebits-onepassword-extension-animated-fill',setTimeout(function(){a&&a.className&&(a.className=a.className.replace(/(\\s)?com-agilebits-onepassword-extension-animated-fill/,''))},F))};document.elementForOPID=z;function K(a,b){var c;c=a.ownerDocument.createEvent('Events');c.initEvent(b,!0,!1);c.charCode=0;c.keyCode=0;c.which=0;c.srcElement=a;c.target=a;return c}function H(a){var b=a.value;C(a,!1);a.dispatchEvent(K(a,'keydown'));a.dispatchEvent(K(a,'keypress'));a.dispatchEvent(K(a,'keyup'));if(''===a.value||a.dataset['com.agilebits.onepassword.initialValue']&&a.value===a.dataset['com.agilebits.onepassword.initialValue'])a.value=b}\
 function I(a){var b=a.value,c=a.ownerDocument.createEvent('HTMLEvents'),d=a.ownerDocument.createEvent('HTMLEvents');a.dispatchEvent(K(a,'keydown'));a.dispatchEvent(K(a,'keypress'));a.dispatchEvent(K(a,'keyup'));d.initEvent('input',!0,!0);a.dispatchEvent(d);c.initEvent('change',!0,!0);a.dispatchEvent(c);a.blur();if(''===a.value||a.dataset['com.agilebits.onepassword.initialValue']&&a.value===a.dataset['com.agilebits.onepassword.initialValue'])a.value=b}\
 function L(){var a=/((\\b|_|-)pin(\\b|_|-)|password|passwort|kennwort|passe|contraseña|senha|密码|adgangskode|hasło|wachtwoord)/i;return Array.prototype.slice.call(B(\"input[type='text']\")).filter(function(b){return b.value&&a.test(b.value)},this)}function D(){L().forEach(function(a){H(a);a.click&&a.click();I(a)})}\
 window.LOGIN_TITLES=[/^\\W*log\\W*[oi]n\\W*$/i,/log\\W*[oi]n (?:securely|now)/i,/^\\W*sign\\W*[oi]n\\W*$/i,'continue','submit','weiter','accès','вход','connexion','entrar','anmelden','accedi','valider','登录','लॉग इन करें'];window.CHANGE_PASSWORD_TITLES=[/^(change|update) password$/i,'save changes','update'];window.LOGIN_RED_HERRING_TITLES=['already have an account','sign in with'];\
 window.REGISTER_TITLES=['register','sign up','signup','join',/^create (my )?(account|profile)$/i,'регистрация','inscription','regístrate','cadastre-se','registrieren','registrazione','注册','साइन अप करें'];window.SEARCH_TITLES='search find поиск найти искать recherche suchen buscar suche ricerca procurar 検索'.split(' ');window.FORGOT_PASSWORD_TITLES='forgot geändert vergessen hilfe changeemail español'.split(' ');window.REMEMBER_ME_TITLES=['remember me','rememberme','keep me signed in'];\
 window.BACK_TITLES=['back','назад'];window.DIVITIS_BUTTON_CLASSES=['button','btn-primary'];function J(a){var b;if(b=h)a:{b=a;for(var c=a.ownerDocument,d=c?c.defaultView:{},e;b&&b!==c;){e=d.getComputedStyle&&b instanceof Element?d.getComputedStyle(b,null):b.style;if(!e){b=!0;break a}if('none'===e.display||'hidden'==e.visibility){b=!1;break a}b=b.parentNode}b=b===c}return b?-1!=='email text password number tel url'.split(' ').indexOf(a.type||''):!1}\
 function z(a){var b;if(void 0===a||null===a)return null;if(b=FieldCollector.b(a))return b;try{var c=Array.prototype.slice.call(B('input, select, button')),d=c.filter(function(b){return b.opid==a});if(0<d.length)b=d[0],1<d.length&&console.warn('More than one element found with opid '+a);else{var e=parseInt(a.split('__')[1],10);isNaN(e)||(b=c[e])}}catch(f){console.error('An unexpected error occurred: '+f)}finally{return b}};function B(a){var b=document,c=[];try{c=b.querySelectorAll(a)}catch(d){console.error('[COMMON] @ag_querySelectorAll Exception in selector \"'+a+'\"')}return c}function C(a,b){if(!a)return!1;var c;b&&(c=a.value);'function'===typeof a.click&&a.click();'function'===typeof a.focus&&a.focus();b&&a.value!==c&&(a.value=c);return'function'===typeof a.click||'function'===typeof a.focus};\
 \
 l(fillScript);\
  return JSON.stringify({'success': true});\
 })\
 \

 """
	
}
