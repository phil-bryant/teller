#pragma once

#include <filesystem>
#include <memory>
#include <string>
#include <vector>

namespace tellercore::ocr {

// One recognized text fragment from an OCR engine. The coordinate contract is
// the single normalization point that keeps the platform-agnostic parser tuned
// once: y/x are normalized into [0,1] with the origin at the bottom-left of the
// page, matching what Apple's Vision returns (boundingBox.midY / minX). Each
// platform backend is responsible for mapping its engine's native coordinates
// into this contract so reconstruct_lines() behaves identically everywhere.
struct Observation {
    double y = 0.0;          // normalized vertical midpoint in [0,1], origin bottom-left
    double x = 0.0;          // normalized left edge in [0,1]
    std::string text;        // trimmed, tab-stripped recognized text
};

// All observations from a single page, in arbitrary engine order. The parser
// clusters and orders them; backends need not pre-sort.
using Page = std::vector<Observation>;

// Thin per-platform OCR adapter. Implementations rasterize a PDF and recognize
// text, returning one Page per source page in page order. This is the only part
// of the statement pipeline that is platform-specific; everything downstream
// (line reconstruction, parsing, persistence) operates on vector<Page>.
class OcrBackend {
public:
    virtual ~OcrBackend() = default;

    OcrBackend(const OcrBackend&) = delete;
    OcrBackend& operator=(const OcrBackend&) = delete;

    // Rasterize + OCR every page of the PDF at pdf_path. Throws ApiError on
    // failure (missing file, decode error, engine unavailable).
    virtual std::vector<Page> recognize(const std::filesystem::path& pdf_path) = 0;

protected:
    OcrBackend() = default;
};

// Returns the OCR backend compiled into this build: the Apple Vision/PDFKit
// adapter on macOS, the Windows.Media.Ocr adapter on Windows. Throws ApiError
// when no backend is available for the current platform.
std::unique_ptr<OcrBackend> make_ocr_backend();

} // namespace tellercore::ocr
