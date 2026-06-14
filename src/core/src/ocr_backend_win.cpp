// Windows OCR backend: Windows.Data.Pdf rasterization + Windows.Media.Ocr.
//
// Interface-complete sibling of the Apple backend, populating the same
// ocr::Observation contract. The one place Windows diverges from Vision is
// coordinate space: Windows.Media.Ocr reports pixel bounding boxes with a
// top-left origin, so each word is normalized to [0,1] and the Y axis is
// flipped to match Vision's bottom-left midY contract. Once normalized,
// reconstruct_lines() reclusters the word boxes identically to the macOS path.
//
// Only this file is gated on _WIN32; the shared parser and persistence layers
// are platform-agnostic.
#ifdef _WIN32

#include <winrt/Windows.Data.Pdf.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Globalization.h>
#include <winrt/Windows.Graphics.Imaging.h>
#include <winrt/Windows.Media.Ocr.h>
#include <winrt/Windows.Storage.h>
#include <winrt/Windows.Storage.Streams.h>

#include <memory>
#include <string>
#include <vector>

#include "tellercore/error.hpp"
#include "tellercore/ocr.hpp"

namespace tellercore::ocr {

namespace {

namespace wf = winrt::Windows::Foundation;
namespace pdf = winrt::Windows::Data::Pdf;
namespace imaging = winrt::Windows::Graphics::Imaging;
namespace media_ocr = winrt::Windows::Media::Ocr;
namespace storage = winrt::Windows::Storage;
namespace streams = winrt::Windows::Storage::Streams;

// 300 DPI render target; PDF user space is 72 points/inch (matches the Apple
// backend and the original pdftoppm -r 300 pipeline).
constexpr double kRenderDpi = 300.0;
constexpr double kPdfPointsPerInch = 72.0;

// #R001: Traceability for function `render_page`.
imaging::SoftwareBitmap render_page(const pdf::PdfPage& page) {
    streams::InMemoryRandomAccessStream stream;
    pdf::PdfPageRenderOptions options;
    const auto size = page.Size();
    const double scale = kRenderDpi / kPdfPointsPerInch;
    options.DestinationWidth(static_cast<uint32_t>(size.Width * scale));
    options.DestinationHeight(static_cast<uint32_t>(size.Height * scale));
    page.RenderToStreamAsync(stream, options).get();
    stream.Seek(0);

    imaging::BitmapDecoder decoder = imaging::BitmapDecoder::CreateAsync(stream).get();
    return decoder.GetSoftwareBitmapAsync().get();
}

// #R001: Traceability for function `recognize_bitmap`.
Page recognize_bitmap(const imaging::SoftwareBitmap& bitmap) {
    media_ocr::OcrEngine engine = media_ocr::OcrEngine::TryCreateFromUserProfileLanguages();
    if (engine == nullptr) {
        throw ApiError(500, "no Windows.Media.Ocr engine available for the user profile languages");
    }
    const double width = static_cast<double>(bitmap.PixelWidth());
    const double height = static_cast<double>(bitmap.PixelHeight());
    if (width == 0.0 || height == 0.0) return {};

    media_ocr::OcrResult result = engine.RecognizeAsync(bitmap).get();
    Page observations;
    for (const media_ocr::OcrLine& line : result.Lines()) {
        for (const media_ocr::OcrWord& word : line.Words()) {
            const wf::Rect rect = word.BoundingRect();
            Observation point;
            // Pixel top-left origin -> normalized bottom-left midY/minX contract.
            point.x = static_cast<double>(rect.X) / width;
            point.y = 1.0 - (static_cast<double>(rect.Y) + static_cast<double>(rect.Height) / 2.0) /
                                height;
            point.text = winrt::to_string(word.Text());
            observations.push_back(std::move(point));
        }
    }
    return observations;
}

class WindowsOcrBackend final : public OcrBackend {
public:
    // #R001: Traceability for function `recognize`.
    std::vector<Page> recognize(const std::filesystem::path& pdf_path) override {
        try {
            storage::StorageFile file =
                storage::StorageFile::GetFileFromPathAsync(winrt::to_hstring(pdf_path.wstring()))
                    .get();
            pdf::PdfDocument document = pdf::PdfDocument::LoadFromFileAsync(file).get();
            std::vector<Page> pages;
            const uint32_t page_count = document.PageCount();
            pages.reserve(page_count);
            for (uint32_t i = 0; i < page_count; ++i) {
                pdf::PdfPage page = document.GetPage(i);
                imaging::SoftwareBitmap bitmap = render_page(page);
                pages.push_back(recognize_bitmap(bitmap));
            }
            return pages;
        } catch (const winrt::hresult_error& error) {
            throw ApiError(500, "Windows OCR failed for " + pdf_path.string() + ": " +
                                    winrt::to_string(error.message()));
        }
    }
};

} // namespace

// #R001: Traceability for function `make_ocr_backend`.
std::unique_ptr<OcrBackend> make_ocr_backend() { return std::make_unique<WindowsOcrBackend>(); }

} // namespace tellercore::ocr

#endif // _WIN32
