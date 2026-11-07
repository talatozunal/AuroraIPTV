import Foundation
import AVFoundation

final class PlayerResourceLoader: NSObject, AVAssetResourceLoaderDelegate, URLSessionTaskDelegate {

    private let originalURL: URL
    
    private static let sharedSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 300
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpShouldUsePipelining = true
        configuration.waitsForConnectivity = true
        configuration.httpMaximumConnectionsPerHost = 4
        return URLSession(configuration: configuration, delegate: SessionDelegate.shared, delegateQueue: nil)
    }()
    
    private class SessionDelegate: NSObject, URLSessionTaskDelegate {
        static let shared = SessionDelegate()
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            var modifiedRequest = request
            if let originalTask = task.currentRequest {
                let headers = ["User-Agent", "Referer", "Origin", "Accept", "Accept-Language", "Connection", "Accept-Encoding"]
                for header in headers {
                    if let value = originalTask.value(forHTTPHeaderField: header) {
                        modifiedRequest.setValue(value, forHTTPHeaderField: header)
                    }
                }
            }
            completionHandler(modifiedRequest)
        }
    }

    init(originalURL: URL) {
        self.originalURL = originalURL
        super.init()
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader,
                        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {

        guard let request = (loadingRequest.request as NSURLRequest).mutableCopy() as? NSMutableURLRequest else {
            return false
        }

        // Convert custom scheme back to http/https, preserving the requested URL (important for redirects)
        if let url = request.url {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            if components?.scheme == "http-custom" {
                components?.scheme = "http"
            } else if components?.scheme == "https-custom" {
                components?.scheme = "https"
            }
            // If host is missing, fall back to original URL's host/path
            if components?.host == nil {
                components = URLComponents(url: originalURL, resolvingAgainstBaseURL: false)
                if originalURL.scheme == "https" {
                    components?.scheme = "https"
                } else {
                    components?.scheme = "http"
                }
                // Try to preserve path/query from requested URL if present
                let requestedPath = url.path
                if !requestedPath.isEmpty && requestedPath != "/" {
                    components?.path = requestedPath
                }
                if let q = url.query, !q.isEmpty {
                    components?.query = q
                }
            }
            if let finalURL = components?.url {
                request.url = finalURL
            }
        }

        // Range header'ını koru (byte-range istekleri için önemli)
        if let range = (loadingRequest.request as URLRequest).value(forHTTPHeaderField: "Range") {
            request.setValue(range, forHTTPHeaderField: "Range")
        }

        if let host = request.url?.host ?? originalURL.host {
            request.setValue("VLC/3.0.18 LibVLC/3.0.18", forHTTPHeaderField: "User-Agent")
            request.setValue("*/*", forHTTPHeaderField: "Accept")
            request.setValue("en-US,en;q=0.9,tr-TR,tr;q=0.8", forHTTPHeaderField: "Accept-Language")
            let scheme = request.url?.scheme ?? originalURL.scheme ?? "http"
            request.setValue("\(scheme)://\(host)/", forHTTPHeaderField: "Referer")
            request.setValue("\(scheme)://\(host)", forHTTPHeaderField: "Origin")
            request.setValue("keep-alive", forHTTPHeaderField: "Connection")
        } else {
            request.setValue("VLC/3.0.18 LibVLC/3.0.18", forHTTPHeaderField: "User-Agent")
            request.setValue("*/*", forHTTPHeaderField: "Accept")
            request.setValue("keep-alive", forHTTPHeaderField: "Connection")
        }
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")

        let dataTask = Self.sharedSession.dataTask(with: request as URLRequest) { [weak self] data, response, error in
            guard let self = self else {
                loadingRequest.finishLoading()
                return
            }

            if let error = error {
                loadingRequest.finishLoading(with: error)
                return
            }

            if let httpResponse = response as? HTTPURLResponse {
                let path = self.originalURL.path.lowercased()
                let fullURL = self.originalURL.absoluteString.lowercased()
                var contentType = httpResponse.mimeType

                if contentType == nil || contentType?.isEmpty == true {
                    if path.contains(".m3u8") || fullURL.contains(".m3u8") {
                        contentType = "application/vnd.apple.mpegurl"
                    } else if path.contains(".ts") {
                        contentType = "video/mp2t"
                    } else if path.contains(".mp4") || fullURL.contains(".mp4") {
                        contentType = "video/mp4"
                    } else if path.contains(".m4v") {
                        contentType = "video/x-m4v"
                    } else if path.contains(".mkv") {
                        contentType = "video/x-matroska"
                    } else if path.contains(".avi") {
                        contentType = "video/x-msvideo"
                    } else if path.contains(".wmv") {
                        contentType = "video/x-ms-wmv"
                    }
                }

                if let contentType = contentType {
                    loadingRequest.contentInformationRequest?.contentType = contentType
                }

                if httpResponse.expectedContentLength > 0 {
                    loadingRequest.contentInformationRequest?.contentLength = httpResponse.expectedContentLength
                }

                // Çoğu VOD sunucusu byte-range destekliyor
                loadingRequest.contentInformationRequest?.isByteRangeAccessSupported = true

                if httpResponse.statusCode >= 400 {
                    let statusError = NSError(domain: NSURLErrorDomain, code: NSURLErrorBadServerResponse, userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode)"])
                    loadingRequest.finishLoading(with: statusError)
                    return
                }
            } else if let response = response {
                loadingRequest.contentInformationRequest?.contentType = response.mimeType
                if response.expectedContentLength > 0 {
                    loadingRequest.contentInformationRequest?.contentLength = response.expectedContentLength
                }
                loadingRequest.contentInformationRequest?.isByteRangeAccessSupported = true
            }

            if let dataRequest = loadingRequest.dataRequest, let data = data, !data.isEmpty {
                if dataRequest.requestsAllDataToEndOfResource {
                    dataRequest.respond(with: data)
                } else {
                    let offset = Int(dataRequest.requestedOffset)
                    let length = dataRequest.requestedLength
                    if dataRequest.currentOffset == 0 && offset == 0 {
                        if length > 0 && length < data.count {
                            dataRequest.respond(with: data.subdata(in: 0..<length))
                        } else {
                            dataRequest.respond(with: data)
                        }
                    } else {
                        // For range requests, respond with the data we got (server may have already sliced)
                        if length > 0 && length <= data.count {
                            dataRequest.respond(with: data.subdata(in: 0..<length))
                        } else {
                            dataRequest.respond(with: data)
                        }
                    }
                }
            }

            loadingRequest.finishLoading()
        }

        dataTask.resume()
        return true
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader,
                        shouldWaitForRenewalOfRequestedResource renewalRequest: AVAssetResourceRenewalRequest) -> Bool {
        return self.resourceLoader(resourceLoader, shouldWaitForLoadingOfRequestedResource: renewalRequest)
    }
}
