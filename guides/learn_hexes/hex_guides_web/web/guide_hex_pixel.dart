import 'dart:html';
import 'dart:math';
import 'package:hex_guides_web/hex.dart';
import 'package:hex_guides_web/axial.dart';
import 'package:hex_guides_web/conversions.dart';
import 'package:hex_guides_web/hex_algorithms.dart'; // For cubeRound

late CanvasElement canvas;
late CanvasRenderingContext2D ctx;

// UI Elements
late InputElement hexSizeInput, axialQIn, axialRIn;
late RadioButtonInputElement pointyTopRadio, flatTopRadio;
late ButtonElement doHexToPixelButton;
late SpanElement pixelResultSpan, clickedPixelInfoSpan, axialResultSpan, cubeResultSpan;
// late SpanElement instructionTextSpan; // Not strictly needed if behavior is clear

// Grid State
double currentHexSize = 30.0;
bool currentIsPointyTop = true;
Axial? highlightedHexForH2P; // Hex from Hex-to-Pixel input
Axial? highlightedHexForP2H; // Hex from Pixel-to-Hex click
Point<double>? markedPixelCenter; // For H2P result

// --- Canvas Drawing & Conversion Logic (needs to be dynamic with hexSize/orientation) ---
Point<double> hexToPixel(Axial hex, double size, bool pointy) {
  double x, y;
  // final widthFactor = pointy ? sqrt(3) : 3.0/2.0; // Not used
  // final heightFactor = pointy ? 3.0/2.0 : sqrt(3); // Not used
  // final qx = pointy ? sqrt(3) : 3.0/2.0; // Not used
  // final qy = pointy ? 0.0 : sqrt(3)/2.0; // Not used
  // final rx = pointy ? sqrt(3)/2.0 : 0.0; // Not used
  // final ry = pointy ? 3.0/2.0 : sqrt(3); // Not used

  if (pointy) {
    x = size * (sqrt(3) * hex.q + sqrt(3) / 2 * hex.r);
    y = size * (3.0 / 2.0 * hex.r);
  } else { // Flat top
    x = size * (3.0 / 2.0 * hex.q);
    y = size * (sqrt(3) / 2 * hex.q + sqrt(3) * hex.r);
  }
  return Point(x + canvas.width! / 2, y + canvas.height! / 2);
}

Axial pixelToAxial(Point<double> pixel, double size, bool pointy) {
    Point<double> pt = Point(
        (pixel.x - canvas.width! / 2) / size,
        (pixel.y - canvas.height! / 2) / size
    );
    double q, r;
    if (pointy) {
        q = (sqrt(3)/3 * pt.x - 1.0/3 * pt.y);
        r = (2.0/3 * pt.y);
    } else { // Flat top
        q = (2.0/3 * pt.x);
        r = (-1.0/3 * pt.x + sqrt(3)/3 * pt.y);
    }
    // Use the public cubeRound from hex_algorithms.dart
    return cubeToAxial(cubeRound(q, r, -q-r));
}

void drawHexOutline(Axial axial, {String strokeStyle = '#cccccc', int lineWidth = 1}) {
    Point<double> center = hexToPixel(axial, currentHexSize, currentIsPointyTop);
    ctx.beginPath();
    for (int i = 0; i < 6; i++) {
        double angle = 2 * pi / 6 * (i + (currentIsPointyTop ? 0.5 : 0));
        double xPos = center.x + currentHexSize * cos(angle);
        double yPos = center.y + currentHexSize * sin(angle);
        if (i == 0) ctx.moveTo(xPos, yPos); else ctx.lineTo(xPos, yPos);
    }
    ctx.closePath();
    ctx.strokeStyle = strokeStyle;
    ctx.lineWidth = lineWidth;
    ctx.stroke();
}

void drawHexFilled(Axial axial, {String fillStyle = 'blue'}) {
    Point<double> center = hexToPixel(axial, currentHexSize, currentIsPointyTop);
    ctx.beginPath();
    for (int i = 0; i < 6; i++) {
        double angle = 2 * pi / 6 * (i + (currentIsPointyTop ? 0.5 : 0));
        double xPos = center.x + currentHexSize * cos(angle);
        double yPos = center.y + currentHexSize * sin(angle);
        if (i == 0) ctx.moveTo(xPos, yPos); else ctx.lineTo(xPos, yPos);
    }
    ctx.closePath();
    ctx.fillStyle = fillStyle;
    ctx.fill();
    ctx.stroke();
}

void drawPixelMarker(Point<double> pixel, {String color = 'red', double radius = 3}) {
    ctx.beginPath();
    ctx.arc(pixel.x, pixel.y, radius, 0, 2 * pi);
    ctx.fillStyle = color;
    ctx.fill();
}

void redrawCanvas() {
    ctx.clearRect(0, 0, canvas.width!, canvas.height!);
    int gridDrawRadius = (max(canvas.width!, canvas.height!) / (currentHexSize * 1.5)).ceil();

    for (int q_ = -gridDrawRadius; q_ <= gridDrawRadius; q_++) {
        for (int r_ = max(-gridDrawRadius, -q_ - gridDrawRadius); r_ <= min(gridDrawRadius, -q_ + gridDrawRadius); r_++) {
            drawHexOutline(Axial(q_,r_));
        }
    }

    if (highlightedHexForH2P != null) {
        drawHexFilled(highlightedHexForH2P!, fillStyle: 'rgba(150, 255, 150, 0.7)'); // Green for H2P
    }
    if (markedPixelCenter != null) {
        drawPixelMarker(markedPixelCenter!);
    }
    if (highlightedHexForP2H != null) {
        drawHexFilled(highlightedHexForP2H!, fillStyle: 'rgba(150, 150, 255, 0.7)'); // Blue for P2H
    }
}

// --- Event Handlers & UI Logic ---
void handleSettingsChange() {
    currentHexSize = double.tryParse(hexSizeInput.value ?? '30') ?? 30.0;
    currentIsPointyTop = pointyTopRadio.checked ?? true;
    // Clear highlights when settings change as pixel coords become invalid
    highlightedHexForH2P = null;
    highlightedHexForP2H = null;
    markedPixelCenter = null;
    pixelResultSpan.text = "(x: -, y: -)";
    clickedPixelInfoSpan.text = "(x: -, y: -)";
    axialResultSpan.text = "q: -, r: -";
    cubeResultSpan.text = "q: -, r: -, s: -";
    redrawCanvas();
}

void performHexToPixel() {
    try {
        int q = int.tryParse(axialQIn.value ?? '') ?? 0;
        int r = int.tryParse(axialRIn.value ?? '') ?? 0;
        highlightedHexForH2P = Axial(q, r);
        markedPixelCenter = hexToPixel(highlightedHexForH2P!, currentHexSize, currentIsPointyTop);
        pixelResultSpan.text = "(x: ${markedPixelCenter!.x.toStringAsFixed(2)}, y: ${markedPixelCenter!.y.toStringAsFixed(2)})";
        highlightedHexForP2H = null; // Clear other highlight
    } catch (e) {
        pixelResultSpan.text = "Invalid input";
        highlightedHexForH2P = null;
        markedPixelCenter = null;
    }
    redrawCanvas();
}

void handleCanvasClick(MouseEvent event) {
    final rect = canvas.getBoundingClientRect();
    final Point<double> clickedPixel = Point((event.client.x - rect.left).toDouble(), (event.client.y - rect.top).toDouble());

    clickedPixelInfoSpan.text = "(x: ${clickedPixel.x.toStringAsFixed(2)}, y: ${clickedPixel.y.toStringAsFixed(2)})";
    highlightedHexForP2H = pixelToAxial(clickedPixel, currentHexSize, currentIsPointyTop);

    Axial resultAxial = highlightedHexForP2H!;
    Hex resultCube = axialToCube(resultAxial);

    axialResultSpan.text = "q: ${resultAxial.q}, r: ${resultAxial.r}";
    cubeResultSpan.text = "q: ${resultCube.q}, r: ${resultCube.r}, s: ${resultCube.s}";

    highlightedHexForH2P = null; // Clear other highlight
    markedPixelCenter = null;
    redrawCanvas();
}

void main() {
    canvas = querySelector('#hexPixelCanvas') as CanvasElement;
    ctx = canvas.getContext('2d') as CanvasRenderingContext2D;

    hexSizeInput = querySelector('#hexSizeInput') as InputElement;
    pointyTopRadio = querySelector('#pointyTopRadio') as RadioButtonInputElement;
    flatTopRadio = querySelector('#flatTopRadio') as RadioButtonInputElement;

    axialQIn = querySelector('#axialQ_in') as InputElement;
    axialRIn = querySelector('#axialR_in') as InputElement;
    doHexToPixelButton = querySelector('#doHexToPixelButton') as ButtonElement;
    pixelResultSpan = querySelector('#pixelResult') as SpanElement;

    clickedPixelInfoSpan = querySelector('#clickedPixelInfo') as SpanElement;
    axialResultSpan = querySelector('#axialResult') as SpanElement;
    cubeResultSpan = querySelector('#cubeResult') as SpanElement;

    hexSizeInput.onChange.listen((_) => handleSettingsChange());
    pointyTopRadio.onChange.listen((_) => handleSettingsChange());
    flatTopRadio.onChange.listen((_) => handleSettingsChange());

    doHexToPixelButton.onClick.listen((_) => performHexToPixel());
    canvas.onClick.listen(handleCanvasClick);

    // Initial setup
    handleSettingsChange(); // This calls redrawCanvas
    performHexToPixel(); // Perform initial H2P with default values
}
