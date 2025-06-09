import 'dart:html';
import 'dart:math';
import 'package:hex_guides_web/hex.dart';
import 'package:hex_guides_web/axial.dart';
import 'package:hex_guides_web/conversions.dart';
import 'package:hex_guides_web/hex_algorithms.dart';

late CanvasElement canvas;
late CanvasRenderingContext2D ctx;
double hexSize = 25.0; // Adjusted for potentially larger area
bool isPointyTop = true;

// UI Elements
late SelectElement modeSelect;
late InputElement radiusInput;
late ButtonElement resetButton;
late SpanElement instructionTextSpan, centerHexCoordsSpan, currentModeInfoSpan, currentRadiusInfoSpan, detailsInfoSpan;

// State
Axial? centerHex;
Set<Axial> obstacles = {};
List<Axial> highlightedHexes = []; // For range or FOV results
String currentMode = 'range'; // 'range' or 'fov'
int currentRadius = 3;


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
        if (i == 0) ctx.moveTo(xPos, yPos);
        else ctx.lineTo(xPos, yPos);
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
        if (i == 0) ctx.moveTo(xPos, yPos);
        else ctx.lineTo(xPos, yPos);
    }
    ctx.closePath();
    ctx.fillStyle = fillStyle;
    ctx.fill();
    ctx.stroke(); // Default border
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
    // Determine grid draw range based on canvas size and hexSize
    int gridDrawRadius = (max(canvas.width!, canvas.height!) / (hexSize * 2.5)).ceil() ;

    for (int q = -gridDrawRadius; q <= gridDrawRadius; q++) {
        for (int r = max(-gridDrawRadius, -q - gridDrawRadius); r <= min(gridDrawRadius, -q + gridDrawRadius); r++) {
            drawHexOutline(Axial(q,r));
        }
    }

    // Highlight hexes in range/FOV
    for (final hex in highlightedHexes) {
        drawHexFilled(hex, fillStyle: 'rgba(173, 216, 230, 0.6)'); // Light blue for range/visible
    }

    // Draw obstacles for FOV
    if (currentMode == 'fov') {
        for (final obstacle in obstacles) {
            drawHexFilled(obstacle, fillStyle: 'rgba(100, 100, 100, 0.8)', label:'X'); // Dark gray for obstacles
        }
    }

    // Highlight center hex
    if (centerHex != null) {
        drawHexFilled(centerHex!, fillStyle: 'rgba(255, 165, 0, 0.9)', label:'C'); // Orange for center
    }
}

// --- Logic for Range and FOV ---
void calculateRange() {
    if (centerHex == null) {
        highlightedHexes.clear();
        return;
    }
    highlightedHexes = axialRange(centerHex!, currentRadius);
}

void calculateFOV() {
    if (centerHex == null) {
        highlightedHexes.clear();
        return;
    }

    List<Axial> visibleHexes = [];
    List<Axial> potentialHexes = axialRange(centerHex!, currentRadius); // Max view distance

    for (final targetHex in potentialHexes) {
        if (targetHex == centerHex) {
            visibleHexes.add(targetHex);
            continue;
        }
        List<Axial> line = axialLineDraw(centerHex!, targetHex);
        bool isVisible = true;
        for (final hexInLine in line) {
            if (hexInLine == centerHex) continue; // Skip the starting point itself
            if (hexInLine == targetHex) break; // Reached target without obstruction on the line
            if (obstacles.contains(hexInLine)) {
                isVisible = false;
                break;
            }
        }
        if (isVisible) {
            visibleHexes.add(targetHex);
        }
    }
    highlightedHexes = visibleHexes;
}


void processVisualization() {
    if (currentMode == 'range') {
        calculateRange();
        detailsInfoSpan.text = centerHex != null ? '${highlightedHexes.length} hexes in range.' : 'Select a center.';
    } else { // fov
        calculateFOV();
        detailsInfoSpan.text = centerHex != null ? '${highlightedHexes.length} hexes visible.' : 'Select a center.';
    }
    redrawCanvas();
}

void updateInfoPanel() {
    centerHexCoordsSpan.text = centerHex != null ? 'q:${centerHex!.q}, r:${centerHex!.r}' : 'None';
    currentModeInfoSpan.text = currentMode == 'range' ? 'Movement Range' : 'Field of View';
    currentRadiusInfoSpan.text = currentRadius.toString();

    if (centerHex == null) {
        instructionTextSpan.text = 'Click on the grid to select a center hex.';
    } else {
        if (currentMode == 'range') {
            instructionTextSpan.text = 'Center selected. Adjust radius or mode.';
        } else { // fov
            instructionTextSpan.text = 'Center selected. Click other hexes to toggle obstacles.';
        }
    }
    processVisualization();
}

void handleCanvasClick(MouseEvent event) {
    final rect = canvas.getBoundingClientRect();
    final mousePos = Point((event.client.x - rect.left).toDouble(), (event.client.y - rect.top).toDouble());
    Axial clickedAxial = pixelToAxial(mousePos);

    if (centerHex == null || clickedAxial == centerHex) {
        centerHex = clickedAxial;
        obstacles.remove(centerHex); // Center cannot be an obstacle
    } else {
        if (currentMode == 'fov') {
            if (obstacles.contains(clickedAxial)) {
                obstacles.remove(clickedAxial);
            } else {
                obstacles.add(clickedAxial);
            }
        } else { // range mode, clicking away from center could mean re-center
            centerHex = clickedAxial;
        }
    }
    updateInfoPanel();
}

void resetState() {
    centerHex = null;
    obstacles.clear();
    currentRadius = int.parse(radiusInput.value ?? "3"); // Reset radius from input
    highlightedHexes.clear();
    updateInfoPanel();
}

void onModeOrRadiusChange() {
    currentMode = modeSelect.value!;
    try {
        currentRadius = int.parse(radiusInput.value!);
        if (currentRadius < 0) currentRadius = 0;
        if (currentRadius > 20) currentRadius = 20; // Max radius limit
        radiusInput.value = currentRadius.toString();
    } catch (e) {
        currentRadius = 3; // default
        radiusInput.value = currentRadius.toString();
    }
    // When mode changes, clear obstacles if switching out of FOV, or if center is null
    if (currentMode != 'fov') {
      obstacles.clear();
    }
    updateInfoPanel(); // This will trigger re-calculation and redraw
}


void main() {
    canvas = querySelector('#hexRangeFovCanvas') as CanvasElement;
    ctx = canvas.getContext('2d') as CanvasRenderingContext2D;

    modeSelect = querySelector('#mode') as SelectElement;
    radiusInput = querySelector('#radiusInput') as InputElement;
    resetButton = querySelector('#resetButton') as ButtonElement;
    instructionTextSpan = querySelector('#instructionText') as SpanElement;
    centerHexCoordsSpan = querySelector('#centerHexCoords') as SpanElement;
    currentModeInfoSpan = querySelector('#currentModeInfo') as SpanElement;
    currentRadiusInfoSpan = querySelector('#currentRadiusInfo') as SpanElement;
    detailsInfoSpan = querySelector('#detailsInfo') as SpanElement;

    resetButton.onClick.listen((_) => resetState());
    canvas.onClick.listen(handleCanvasClick);
    modeSelect.onChange.listen((_) => onModeOrRadiusChange());
    radiusInput.onChange.listen((_) => onModeOrRadiusChange());
    radiusInput.onInput.listen((_) { // Update more dynamically on input
        try {
            int val = int.parse(radiusInput.value!);
             if (val >=0 && val <=20) { // Basic validation during typing
                currentRadius = val;
                // No full updateInfoPanel here to avoid lag, just store. onChange will do full update.
             }
        } catch (e) { /* ignore parsing errors during typing */ }
    });


    // Initial setup
    resetState(); // This also calls updateInfoPanel which calls redrawCanvas
}
