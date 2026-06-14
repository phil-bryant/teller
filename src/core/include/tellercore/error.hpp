#pragma once

#include <stdexcept>
#include <string>

namespace tellercore {

// Mirrors the typed errors the Python stack raised (TellerAPIError /
// MailcartError / ValueError): a status code plus a human-readable detail.
// FFI adapters and CLI tools map it onto exit codes or JSON error envelopes.
class ApiError : public std::runtime_error {
public:
    // #R001: Traceability for function `ApiError`.
    ApiError(int status, std::string detail)
        : std::runtime_error(detail), status_(status), detail_(std::move(detail)) {}

    // #R001: Traceability for function `status`.
    int status() const noexcept { return status_; }
    // #R001: Traceability for function `detail`.
    const std::string& detail() const noexcept { return detail_; }

private:
    int status_;
    std::string detail_;
};

} // namespace tellercore
