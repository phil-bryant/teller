// NOLINTBEGIN(concurrency-mt-unsafe,bugprone-easily-swappable-parameters)
#include "tellercore/mailcart.hpp"

#include <cstdlib>

#ifdef TELLERCORE_ENABLE_HTTP
#include <httplib.h>
#endif

namespace tellercore::mailcart {

namespace {

constexpr const char* kBaseUrlEnv = "MAILCART_SERVICE_BASE_URL";
constexpr const char* kTokenEnv = "MAILCART_SERVICE_TOKEN";
constexpr const char* kDefaultBaseUrl = "https://127.0.0.1:8788";

// #R001: Traceability for function `env_or_empty`.
std::string env_or_empty(const char* name) {
    const char* value = std::getenv(name);
    return value ? std::string(value) : std::string();
}

// #R001: Traceability for function `is_loopback_host`.
bool is_loopback_host(const std::string& host) {
    return host == "localhost" || host == "127.0.0.1" || host == "::1" || host.rfind("127.", 0) == 0;
}

struct ParsedUrl {
    std::string host;
    int port = 443;
};

// #R001: Traceability for function `parse_https_base_url`.
ParsedUrl parse_https_base_url(const std::string& base_url) {
    std::string normalized = base_url;
    while (!normalized.empty() && (normalized.back() == '/' || normalized.back() == ' ')) {
        normalized.pop_back();
    }
    const std::string prefix = "https://";
    std::string rest = normalized.substr(prefix.size());
    const auto slash = rest.find('/');
    if (slash != std::string::npos) rest = rest.substr(0, slash);
    ParsedUrl out;
    const auto colon = rest.rfind(':');
    if (colon != std::string::npos && rest.find(']') == std::string::npos) {
        out.host = rest.substr(0, colon);
        try {
            out.port = std::stoi(rest.substr(colon + 1));
        } catch (...) {
            out.port = 443;
        }
    } else {
        out.host = rest;
    }
    return out;
}

#ifdef TELLERCORE_ENABLE_HTTP
class HttpClient final : public Client {
public:
    // #R001: Traceability for function `HttpClient`.
    HttpClient(const std::string& base_url, std::string token, double timeout_seconds)
        : token_(std::move(token)) {
        const ParsedUrl parsed = parse_https_base_url(base_url);
        client_ = std::make_unique<httplib::SSLClient>(parsed.host, parsed.port);
        if (is_loopback_host(parsed.host)) {
            // Local Mailcart HTTPS commonly uses a self-signed cert in development;
            // keep transport encrypted while allowing loopback certs.
            client_->enable_server_certificate_verification(false);
        }
        const auto secs = static_cast<time_t>(timeout_seconds);
        const auto usecs = static_cast<time_t>((timeout_seconds - static_cast<double>(secs)) * 1e6);
        client_->set_connection_timeout(secs, usecs);
        client_->set_read_timeout(secs, usecs);
        client_->set_write_timeout(secs, usecs);
    }

    // #R001: Traceability for function `get_message`.
    json get_message(const std::string& email_message_id) override {
        return request("/v1/messages/" + email_message_id);
    }

    // #R001: Traceability for function `search`.
    json search(const std::string& query, int limit) override {
        httplib::Params params{{"query", query}, {"limit", std::to_string(limit)}};
        return request("/v1/messages/search?" + httplib::detail::params_to_query_str(params));
    }

private:
    // #R001: Traceability for function `request`.
    json request(const std::string& path) {
        httplib::Headers headers{{"Accept", "application/json"}};
        if (!token_.empty()) headers.emplace("Authorization", "Bearer " + token_);
        auto result = client_->Get(path, headers);
        if (!result) {
            throw MailcartError{502, "mailcart: request failed: " + httplib::to_string(result.error())};
        }
        if (result->status >= 200 && result->status < 300) {
            json parsed = json::parse(result->body, nullptr, false);
            if (parsed.is_discarded()) {
                throw MailcartError{502, "mailcart: response was not valid JSON"};
            }
            return parsed;
        }
        if (result->status == 404) throw MailcartError{404, "mailcart: message not found"};
        std::string preview = result->body.substr(0, 200);
        for (auto& c : preview) {
            if (c == '\n') c = ' ';
        }
        throw MailcartError{502, "mailcart: upstream returned " + std::to_string(result->status) +
                                     ": " + preview};
    }

    std::string token_;
    std::unique_ptr<httplib::SSLClient> client_;
};
#endif // TELLERCORE_ENABLE_HTTP

} // namespace

// #R001: Traceability for function `validated_https_base_url`.
std::string validated_https_base_url(const std::string& base_url) {
    std::string normalized = base_url;
    const auto begin = normalized.find_first_not_of(" \t\r\n");
    if (begin == std::string::npos) {
        throw MailcartError{503, std::string("mailcart: ") + kBaseUrlEnv +
                                     " must be configured with an https URL"};
    }
    const auto end = normalized.find_last_not_of(" \t\r\n");
    normalized = normalized.substr(begin, end - begin + 1);
    const std::string prefix = "https://";
    if (normalized.rfind(prefix, 0) != 0) {
        throw MailcartError{503, std::string("mailcart: ") + kBaseUrlEnv +
                                     " must use https (received: " + normalized + ")"};
    }
    std::string rest = normalized.substr(prefix.size());
    const auto slash = rest.find('/');
    if (slash != std::string::npos) rest = rest.substr(0, slash);
    if (rest.empty()) {
        throw MailcartError{503, std::string("mailcart: ") + kBaseUrlEnv + " must include a host"};
    }
    return normalized;
}

#ifdef TELLERCORE_ENABLE_HTTP
// #R001: Traceability for function `make_http_client`.
std::unique_ptr<Client> make_http_client(const std::string& base_url, const std::string& token,
                                         double timeout_seconds) {
    return std::make_unique<HttpClient>(validated_https_base_url(base_url), token, timeout_seconds);
}

// #R001: Traceability for function `make_default_client`.
std::unique_ptr<Client> make_default_client() {
    std::string base_url = env_or_empty(kBaseUrlEnv);
    if (base_url.empty()) base_url = kDefaultBaseUrl;
    return make_http_client(base_url, env_or_empty(kTokenEnv));
}
#else
// #R001: Traceability for function `make_http_client`.
std::unique_ptr<Client> make_http_client(const std::string& base_url, const std::string&, double) {
    validated_https_base_url(base_url);
    return nullptr;
}

// #R001: Traceability for function `make_default_client`.
std::unique_ptr<Client> make_default_client() { return nullptr; }
#endif

} // namespace tellercore::mailcart
// NOLINTEND(concurrency-mt-unsafe,bugprone-easily-swappable-parameters)
