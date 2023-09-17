//
//  AuthManager.swift
//  spotify
//
//  Created by Lukáš Pisarčík on 27/08/2023.
//

import Foundation


final class AuthManager {
    static let shared = AuthManager()
    private var refreshingToken = false
    
    struct Constants {
        static let clientID = "472f919af4ec412ba73b9832661e7ab5"
        static let clientSecret = "e0b0334bde144a82a17fb1959eb86c9d"
        static let tokenAPIURL = "https://accounts.spotify.com/api/token"
        static let scopes = "user-read-private%20playlist-read-private%20playlist-modify-private%20playlist-modify-public%20user-follow-read%20user-library-read%20user-read-email"
    }
    
    public var signInURL: URL? {
        let redirectURI = "https://www.iosacademy.io/"
        let base = "https://accounts.spotify.com/authorize"
        let string = "\(base)?response_type=code&client_id=\(Constants.clientID)&scope=\(Constants.scopes)&redirect_uri=\(redirectURI)&show_dialog=TRUE"
        return URL(string: string)
    }
    
    private init(){}
    
    var isSignedIn: Bool {
        return accessToken != nil
    }
    
    private var accessToken: String? {
        return UserDefaults.standard.string(forKey: "access_token")
    }
    
    private var refreshToken: String? {
        return UserDefaults.standard.string(forKey: "refresh_token")
    }
    
    private var tokenExpirationDate: Date? {
        return UserDefaults.standard.object(forKey: "expirationDate") as? Date
    }
    
    private var shouldRefreshToken: Bool {
        guard let expirationDate = tokenExpirationDate else {
            return false
        }
        let currentDate = Date()
        let fiveMinutes: TimeInterval = 300
        return currentDate.addingTimeInterval(fiveMinutes) >= expirationDate
    }
    
    public func exchangeCodeForAccessToken(_ code: String, _ completion: @escaping (Bool) -> Void) {
        // Get token
        guard let url = URL(string: Constants.tokenAPIURL) else {
            return
        }
        
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "redirect_uri", value: "https://www.iosacademy.io/")
        ]
        
        let basicToken = Constants.clientID + ":" + Constants.clientSecret
        let data = basicToken.data(using: .utf8)
        guard let base64String = data?.base64EncodedString() else {
            print("Fail to get base64 format")
            completion(false)
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = components.query?.data(using: .utf8)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("Basic \(base64String)", forHTTPHeaderField: "Authorization")
        
        let task = URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let data = data,
                  error == nil else {
                completion(false)
                return
            }
            
            do {
                let result = try JSONDecoder().decode(AuthResponse.self, from: data)
                self?.cacheToken(result)
                completion(true)
            } catch {
                print(error.localizedDescription)
                completion(false)
            }
        }
        
        task.resume()
        
    }
    
    private func cacheToken(_ authResponse: AuthResponse){
        UserDefaults.standard.setValue(authResponse.access_token, forKey: "access_token")
        if let refresh_token = authResponse.refresh_token {
            UserDefaults.standard.setValue(refresh_token, forKey: "refresh_token")
        }
        UserDefaults.standard.setValue(Date().addingTimeInterval(TimeInterval(authResponse.expires_in)), forKey: "expires_in")
    }
    
    private var onRefreshBlocks = [((String) -> Void)] ()
    
    public func withValidToken(completion: @escaping (String) -> Void){
        guard !refreshingToken else {
            onRefreshBlocks.append(completion)
            return
        }
        if shouldRefreshToken {
            // refresh
            refreshIfNeeded { [weak self] success in
                    if let token = self?.accessToken, success {
                        completion(token)
                }
            }
        } else if let token = accessToken {
            completion(token)
        }
    }
    
    public func refreshIfNeeded(completion: ((Bool) -> Void)?) {
        guard !refreshingToken else {
            return
        }
        guard shouldRefreshToken else {
            completion?(true)
            return
        }
        guard let refreshToken = self.refreshToken else {
            return
        }
        
        guard let url = URL(string: Constants.tokenAPIURL) else {
            return
        }
        
        refreshingToken = true
        
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "grant_type", value: "refresh"),
            URLQueryItem(name: "refresh_token", value: refreshToken)
        ]
        
        let basicToken = Constants.clientID + ":" + Constants.clientSecret
        let data = basicToken.data(using: .utf8)
        guard let base64String = data?.base64EncodedString() else {
            print("Fail to get base64 format")
            completion?(false)
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = components.query?.data(using: .utf8)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("Basic \(base64String)", forHTTPHeaderField: "Authorization")
        
        let task = URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            self?.refreshingToken = false
            guard let data = data,
                  error == nil else {
                completion?(false)
                return
            }
            
            do {
                let result = try JSONDecoder().decode(AuthResponse.self, from: data)
                self?.onRefreshBlocks.forEach{ $0(result.access_token) }
                self?.onRefreshBlocks.removeAll()
                self?.cacheToken(result)
                completion?(true)
            } catch {
                print(error.localizedDescription)
                completion?(false)
            }
        }
        
        task.resume()
        
    }
}
