// Apple OCR backend: PDFKit rasterization + Vision text recognition.
//
// Replaces the Python pdftoppm + `swift -e` Vision snippet (08 lines 86-158)
// with native calls that populate the shared ocr::Observation contract directly
// (Vision already reports normalized bottom-left [0,1] bounding boxes, so no
// coordinate remapping is needed here). Compiled as Objective-C++ with ARC.
#ifdef __APPLE__

#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>
#import <PDFKit/PDFKit.h>
#import <Vision/Vision.h>

#include <cmath>
#include <memory>
#include <vector>

#include "tellercore/error.hpp"
#include "tellercore/ocr.hpp"

namespace tellercore::ocr {

namespace {

// 300 DPI render (PDF user space is 72 points/inch), matching the Python
// pipeline's `pdftoppm -r 300`.
constexpr double kRenderDpi = 300.0;
constexpr double kPdfPointsPerInch = 72.0;

CGImageRef render_page(PDFPage* page) {
    const CGRect box = [page boundsForBox:kPDFDisplayBoxMediaBox];
    const double scale = kRenderDpi / kPdfPointsPerInch;
    const size_t width = static_cast<size_t>(std::ceil(box.size.width * scale));
    const size_t height = static_cast<size_t>(std::ceil(box.size.height * scale));
    if (width == 0 || height == 0) return nullptr;

    CGColorSpaceRef color_space = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(nullptr, width, height, 8, 0, color_space,
                                             kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(color_space);
    if (!ctx) return nullptr;

    CGContextSetRGBFillColor(ctx, 1.0, 1.0, 1.0, 1.0);
    CGContextFillRect(ctx, CGRectMake(0, 0, static_cast<CGFloat>(width), static_cast<CGFloat>(height)));
    CGContextScaleCTM(ctx, static_cast<CGFloat>(scale), static_cast<CGFloat>(scale));
    CGContextTranslateCTM(ctx, -box.origin.x, -box.origin.y);
    [page drawWithBox:kPDFDisplayBoxMediaBox toContext:ctx];

    CGImageRef image = CGBitmapContextCreateImage(ctx);
    CGContextRelease(ctx);
    return image;
}

Page recognize_image(CGImageRef image) {
    Page observations;
    VNRecognizeTextRequest* request = [[VNRecognizeTextRequest alloc] init];
    request.recognitionLevel = VNRequestTextRecognitionLevelAccurate;
    request.usesLanguageCorrection = NO;

    VNImageRequestHandler* handler = [[VNImageRequestHandler alloc] initWithCGImage:image options:@{}];
    NSError* error = nil;
    if (![handler performRequests:@[ request ] error:&error]) {
        const std::string detail =
            error ? std::string(error.localizedDescription.UTF8String) : "Vision OCR failed";
        throw ApiError(500, "Vision OCR failed: " + detail);
    }

    for (VNRecognizedTextObservation* obs in request.results) {
        VNRecognizedText* top = [[obs topCandidates:1] firstObject];
        if (top == nil) continue;
        NSString* trimmed = [top.string
            stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (trimmed.length == 0) continue;
        NSString* sanitized = [trimmed stringByReplacingOccurrencesOfString:@"\t" withString:@" "];
        const CGRect bbox = obs.boundingBox;
        Observation point;
        point.y = static_cast<double>(CGRectGetMidY(bbox));
        point.x = static_cast<double>(CGRectGetMinX(bbox));
        point.text = sanitized.UTF8String;
        observations.push_back(std::move(point));
    }
    return observations;
}

class AppleOcrBackend final : public OcrBackend {
public:
    std::vector<Page> recognize(const std::filesystem::path& pdf_path) override {
        @autoreleasepool {
            NSString* path = [NSString stringWithUTF8String:pdf_path.c_str()];
            NSURL* url = [NSURL fileURLWithPath:path];
            PDFDocument* document = [[PDFDocument alloc] initWithURL:url];
            if (document == nil) {
                throw ApiError(422, "failed to load PDF: " + pdf_path.string());
            }
            std::vector<Page> pages;
            const NSUInteger page_count = document.pageCount;
            pages.reserve(page_count);
            for (NSUInteger i = 0; i < page_count; ++i) {
                @autoreleasepool {
                    PDFPage* page = [document pageAtIndex:i];
                    if (page == nil) {
                        pages.emplace_back();
                        continue;
                    }
                    CGImageRef image = render_page(page);
                    if (image == nullptr) {
                        throw ApiError(500, "failed to rasterize PDF page " + std::to_string(i) +
                                                " of " + pdf_path.string());
                    }
                    Page observations = recognize_image(image);
                    CGImageRelease(image);
                    pages.push_back(std::move(observations));
                }
            }
            return pages;
        }
    }
};

} // namespace

std::unique_ptr<OcrBackend> make_ocr_backend() { return std::make_unique<AppleOcrBackend>(); }

} // namespace tellercore::ocr

#endif // __APPLE__
