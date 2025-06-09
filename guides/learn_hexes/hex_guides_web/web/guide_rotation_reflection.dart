import 'dart:html';
import 'dart:math';
import 'package:hex_guides_web/hex.dart';
import 'package:hex_guides_web/axial.dart';
import 'package:hex_guides_web/conversions.dart';
import 'package:hex_guides_web/hex_algorithms.dart';

late CanvasElement canvas;
late CanvasRenderingContext2D ctx;
double hexSize = 28.0;
bool isPointyTop = true;

// UI Elements
late ButtonElement modeSelectHexesButton, modeSelectCenterButton, rotateRightButton, rotateLeftButton;
late ButtonElement reflectQButton, reflectRButton, reflectSButton, clearAllButton;
late SpanElement instructionTextSpan, currentModeDisplaySpan;
late SpanElement patternHexesCountSpan, centerHexCoordsSpan, transformedHexesCountSpan;

// State
String currentSelectionMode = 'pattern'; // 'pattern' or 'center'
Set<Axial> patternHexes = {};
Set<Axial> transformedHexes = {};
Axial? operationCenter;
Axial originAxial = Axial(0,0); // For vector calculations

// --- Canvas Drawing ---
Point<double> hexToPixel(Axial hex) {
  double x, y;
  if (isPointyTop) {
    x = hexSize * (sqrt(3) * hex.q + sqrt(3) / 2 * hex.r);
    y = hexSize * (3.0 / 2.0 * hex.r);
  } else {
    x = hexSize * (3.0 / 2.0 * hex.q);
    y = hexSize * (sqrt(3) / 2 * hex.q + sqrt(3) * hex.r);
  }
  return Point(x + canvas.width! / 2, y + canvas.height! / 2);
}

Axial pixelToAxial(Point<double> p) {
    Point<double> pt = Point(
        (p.x - canvas.width! / 2) / hexSize,
        (p.y - canvas.height! / 2) / hexSize
    );
    double q, r;
    if (isPointyTop) {
        q = (sqrt(3)/3 * pt.x - 1.0/3 * pt.y);
        r = (2.0/3 * pt.y);
    } else {
        q = (2.0/3 * pt.x);
        r = (-1.0/3 * pt.x + sqrt(3)/3 * pt.y);
    }
    return cubeToAxial(cubeRound(q, r, -q-r));
}

void drawHexOutline(Axial axial, {String strokeStyle = '#cccccc', int lineWidth = 1}) {
    Point<double> center = hexToPixel(axial);
    ctx.beginPath();
    for (int i = 0; i < 6; i++) {
        double angle = 2 * pi / 6 * (i + (isPointyTop ? 0.5 : 0));
        double xPos = center.x + hexSize * cos(angle);
        double yPos = center.y + hexSize * sin(angle);
        if (i == 0) ctx.moveTo(xPos, yPos); else ctx.lineTo(xPos, yPos);
    }
    ctx.closePath();
    ctx.strokeStyle = strokeStyle;
    ctx.lineWidth = lineWidth;
    ctx.stroke();
}

void drawHexFilled(Axial axial, {String fillStyle = 'blue', String? label, String labelColor = 'black'}) {
    Point<double> center = hexToPixel(axial);
    ctx.beginPath();
    for (int i = 0; i < 6; i++) {
        double angle = 2 * pi / 6 * (i + (isPointyTop ? 0.5 : 0));
        double xPos = center.x + hexSize * cos(angle);
        double yPos = center.y + hexSize * sin(angle);
        if (i == 0) ctx.moveTo(xPos, yPos); else ctx.lineTo(xPos, yPos);
    }
    ctx.closePath();
    ctx.fillStyle = fillStyle;
    ctx.fill();
    ctx.stroke();
    if (label != null) {
        ctx.fillStyle = labelColor;
        ctx.font = 'bold 10px sans-serif';
        ctx.textAlign = 'center';
        ctx.textBaseline = 'middle';
        ctx.fillText(label, center.x, center.y);
    }
}

void redrawCanvas() {
    ctx.clearRect(0, 0, canvas.width!, canvas.height!);
    int gridDrawRadius = (max(canvas.width!, canvas.height!) / (hexSize * 2.5)).ceil();
    for (int q = -gridDrawRadius; q <= gridDrawRadius; q++) {
        for (int r = max(-gridDrawRadius, -q - gridDrawRadius); r <= min(gridDrawRadius, -q + gridDrawRadius); r++) {
            drawHexOutline(Axial(q,r));
        }
    }

    for (final hex in patternHexes) {
        drawHexFilled(hex, fillStyle: 'rgba(150, 150, 255, 0.7)'); // Light blue for pattern
    }
    for (final hex in transformedHexes) {
        drawHexFilled(hex, fillStyle: 'rgba(150, 255, 150, 0.7)'); // Light green for transformed
    }
    if (operationCenter != null) {
        drawHexFilled(operationCenter!, fillStyle: 'rgba(255, 165, 0, 0.9)', label: 'C'); // Orange for center
    }
}

// --- Transformation Logic ---
void applyRotation(bool clockwise) {
    if (operationCenter == null || patternHexes.isEmpty) return;
    transformedHexes.clear();
    for (final p_hex in patternHexes) {
        Axial vec = p_hex - operationCenter!; // Vector from center to pattern hex
        Axial rotatedVec = clockwise ? axialRotateRight(vec) : axialRotateLeft(vec);
        transformedHexes.add(operationCenter! + rotatedVec);
    }
    updateInfoPanel();
}

void applyReflection(String axis) { // axis: 'q', 'r', or 's'
    if (operationCenter == null || patternHexes.isEmpty) return;
    transformedHexes.clear();
    for (final p_hex in patternHexes) { // Corrected variable name
        Axial vec = p_hex - operationCenter!; // Vector from center to pattern hex
        Axial reflectedVec;
        // Perform reflection as if vec is from origin (0,0)
        if (axis == 'q') reflectedVec = axialReflectQ(vec);
        else if (axis == 'r') reflectedVec = axialReflectR(vec);
        else reflectedVec = axialReflectS(vec); // 's'
        transformedHexes.add(operationCenter! + reflectedVec);
    }
    updateInfoPanel();
}


void updateInfoPanel() {
    patternHexesCountSpan.text = patternHexes.length.toString();
    centerHexCoordsSpan.text = operationCenter != null ? 'q:${operationCenter!.q}, r:${operationCenter!.r}' : 'None';
    transformedHexesCountSpan.text = transformedHexes.length.toString();

    currentModeDisplaySpan.text = currentSelectionMode == 'pattern' ? "Selecting Pattern Hexes" : "Selecting Operation Center";
    if (currentSelectionMode == 'pattern') {
        instructionTextSpan.text = 'Click hexes to add/remove from pattern. Then select an operation center.';
    } else {
        instructionTextSpan.text = 'Click a hex to set it as the operation center.';
    }
    redrawCanvas();
}

void handleCanvasClick(MouseEvent event) {
    final rect = canvas.getBoundingClientRect();
    final mousePos = Point((event.client.x - rect.left).toDouble(), (event.client.y - rect.top).toDouble());
    Axial clickedAxial = pixelToAxial(mousePos);

    if (currentSelectionMode == 'pattern') {
        if (patternHexes.contains(clickedAxial)) {
            patternHexes.remove(clickedAxial);
        } else {
            patternHexes.add(clickedAxial);
        }
        transformedHexes.clear(); // Clear transformed when pattern changes
    } else { // 'center'
        operationCenter = clickedAxial;
        transformedHexes.clear(); // Clear transformed when center changes
    }
    updateInfoPanel();
}

void setSelectionMode(String mode) {
    currentSelectionMode = mode;
    updateInfoPanel();
}

void clearAll() {
    patternHexes.clear();
    transformedHexes.clear();
    operationCenter = null;
    setSelectionMode('pattern'); // Reset mode
}

void main() {
    canvas = querySelector('#hexTransformCanvas') as CanvasElement;
    ctx = canvas.getContext('2d') as CanvasRenderingContext2D;

    modeSelectHexesButton = querySelector('#modeSelectHexesButton') as ButtonElement;
    modeSelectCenterButton = querySelector('#modeSelectCenterButton') as ButtonElement;
    rotateRightButton = querySelector('#rotateRightButton') as ButtonElement;
    rotateLeftButton = querySelector('#rotateLeftButton') as ButtonElement;
    reflectQButton = querySelector('#reflectQButton') as ButtonElement;
    reflectRButton = querySelector('#reflectRButton') as ButtonElement;
    reflectSButton = querySelector('#reflectSButton') as ButtonElement;
    clearAllButton = querySelector('#clearAllButton') as ButtonElement;

    instructionTextSpan = querySelector('#instructionText') as SpanElement;
    currentModeDisplaySpan = querySelector('#currentModeDisplay') as SpanElement;
    patternHexesCountSpan = querySelector('#patternHexesCount') as SpanElement;
    centerHexCoordsSpan = querySelector('#centerHexCoords') as SpanElement;
    transformedHexesCountSpan = querySelector('#transformedHexesCount') as SpanElement;

    modeSelectHexesButton.onClick.listen((_) => setSelectionMode('pattern'));
    modeSelectCenterButton.onClick.listen((_) => setSelectionMode('center'));

    rotateRightButton.onClick.listen((_) => applyRotation(true));
    rotateLeftButton.onClick.listen((_) => applyRotation(false));
    reflectQButton.onClick.listen((_) => applyReflection('q'));
    reflectRButton.onClick.listen((_) => applyReflection('r'));
    reflectSButton.onClick.listen((_) => applyReflection('s'));

    clearAllButton.onClick.listen((_) => clearAll());
    canvas.onClick.listen(handleCanvasClick);

    clearAll(); // Initial setup
}
