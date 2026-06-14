#pragma once

#include <memory>
#include <string>

#include <nlohmann/json.hpp>

namespace tellercore::mailcart {

using nlohmann::json;

// Typed transport/upstream failure, port of teller_mailcart_client.MailcartError.
struct MailcartError {
    int status_code = 0;
    std::string message;
};

// Abstract transport so tests and offline mode can substitute fakes.
class Client {
public:
    // #R001: Traceability for function `Client`.
    virtual ~Client() = default;
    // Throws MailcartError on transport/upstream failure.
    virtual json get_message(const std::string& email_message_id) = 0;
    virtual json search(const std::string& query, int limit) = 0;
};

// HTTPS client against the Mac-local mailcart service. Loopback hosts accept
// self-signed certs (matching teller_mailcart_client.py). Base URL must be https.
std::unique_ptr<Client> make_http_client(const std::string& base_url, const std::string& token,
                                         double timeout_seconds = 12.0);

// Resolves MAILCART_SERVICE_BASE_URL / MAILCART_SERVICE_TOKEN with the Python
// defaults. Throws MailcartError{503,...} for non-https configuration.
std::unique_ptr<Client> make_default_client();

// Validates an https base URL, throwing MailcartError{503,...} on a bad scheme/
// host (port of _validated_https_base_url). Exposed for unit tests.
std::string validated_https_base_url(const std::string& base_url);

} // namespace tellercore::mailcart
