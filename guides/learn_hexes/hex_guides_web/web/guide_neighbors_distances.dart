import 'dart:html';
import 'dart:math';
import 'package:hex_guides_web/hex.dart';
import 'package:hex_guides_web/axial.dart';
import 'package:hex_guides_web/conversions.dart';
import 'package:hex_guides_web/hex_algorithms.dart';

late CanvasElement canvas;
late CanvasRenderingContext2D ctx;
double hexSize = 30.0;
bool isPointyTop = true; // Keep consistent with other guides, can be a toggle later

// UI Elements
late ButtonElement resetButton;
late SpanElement instructionTextSpan;
late SpanElement hexACoordsSpan, hexBCoordsSpan, hexANeighborsInfoSpan, distanceInfoSpan;

// State
Axial? selectedHexA;
Axial? selectedHexB;
List<Axial> neighborsOfA = [];
List<Axial> lineAtoB = [];

// --- Canvas Drawing (adapted from previous guides) ---
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
    return cubeToAxial(cubeRound(q, r, -q-r)); // Use public cubeRound from hex_algorithms
}

void drawHexOutline(Axial axial, {String strokeStyle = '#cccccc', int lineWidth = 1, String? label}) {
    Point<double> center = hexToPixel(axial);
    ctx.beginPath();
    for (int i = 0; i < 6; i++) {
        double angle = 2 * pi / 6 * (i + (isPointyTop ? 0.5 : 0));
        double x = center.x + hexSize * cos(angle);
        double y = center.y + hexSize * sin(angle);
        if (i == 0) ctx.moveTo(x, y);
        else ctx.lineTo(x, y);
    }
    ctx.closePath();
    ctx.strokeStyle = strokeStyle;
    ctx.lineWidth = lineWidth;
    ctx.stroke();
     if (label != null) {
        ctx.fillStyle = 'black';
        ctx.font = '10px sans-serif';
        ctx.textAlign = 'center';
        ctx.textBaseline = 'middle';
        ctx.fillText(label, center.x, center.y);
    }
}

void drawHexFilled(Axial axial, {String fillStyle = 'blue', String? label}) {
    Point<double> center = hexToPixel(axial);
    ctx.beginPath();
    for (int i = 0; i < 6; i++) {
        double angle = 2 * pi / 6 * (i + (isPointyTop ? 0.5 : 0));
        double x = center.x + hexSize * cos(angle);
        double y = center.y + hexSize * sin(angle);
        if (i == 0) ctx.moveTo(x, y);
        else ctx.lineTo(x, y);
    }
    ctx.closePath();
    ctx.fillStyle = fillStyle;
    ctx.fill();
    ctx.stroke(); // Default border
     if (label != null) {
        ctx.fillStyle = 'white'; // Assuming dark fill
        ctx.font = '10px sans-serif';
        ctx.textAlign = 'center';
        ctx.textBaseline = 'middle';
        ctx.fillText(label, center.x, center.y);
    }
}

void drawLineBetweenHexes(Axial h1, Axial h2, {String strokeStyle = 'green', int lineWidth = 2}) {
    Point p1 = hexToPixel(h1);
    Point p2 = hexToPixel(h2);
    ctx.beginPath();
    ctx.moveTo(p1.x, p1.y);
    ctx.lineTo(p2.x, p2.y);
    ctx.strokeStyle = strokeStyle;
    ctx.lineWidth = lineWidth;
    ctx.stroke();
}


void redrawCanvas() {
    ctx.clearRect(0, 0, canvas.width!, canvas.height!);
    int range = (canvas.width! / (hexSize * (isPointyTop ? sqrt(3) : 1.5))) ~/ 3 + 1; // Smaller default grid
    for (int q = -range; q <= range; q++) {
        for (int r = max(-range, -q - range); r <= min(range, -q + range); r++) {
            drawHexOutline(Axial(q,r));
        }
    }

    // Draw line between A and B if both selected
    if (selectedHexA != null && selectedHexB != null) {
        // Draw the line composed of hexes first
        lineAtoB.forEach((hex) {
             if (hex != selectedHexA && hex != selectedHexB) { // Don't overdraw A and B centers
                drawHexFilled(hex, fillStyle: 'rgba(150, 250, 150, 0.4)'); // Light green for path
             }
        });
        // Draw a direct line on top
        // drawLineBetweenHexes(selectedHexA!, selectedHexB!);
    }


    // Highlight neighbors of A
    for (final neighbor in neighborsOfA) {
        drawHexFilled(neighbor, fillStyle: 'rgba(255, 255, 100, 0.7)'); // Yellow for neighbors
    }

    // Highlight selected hexes
    if (selectedHexA != null) {
        drawHexFilled(selectedHexA!, fillStyle: 'rgba(100, 100, 255, 0.8)', label: 'A'); // Blue for A
    }
    if (selectedHexB != null) {
        drawHexFilled(selectedHexB!, fillStyle: 'rgba(255, 100, 100, 0.8)', label: 'B'); // Red for B
    }
}

void updateInfoPanel() {
    hexACoordsSpan.text = selectedHexA != null ? 'q:${selectedHexA!.q}, r:${selectedHexA!.r}' : '-';
    hexBCoordsSpan.text = selectedHexB != null ? 'q:${selectedHexB!.q}, r:${selectedHexB!.r}' : '-';

    if (selectedHexA != null) {
        neighborsOfA = List.generate(6, (i) => axialNeighbor(selectedHexA!, i));
        hexANeighborsInfoSpan.text = 'Highlighted in yellow';
    } else {
        neighborsOfA.clear();
        hexANeighborsInfoSpan.text = '-';
    }

    if (selectedHexA != null && selectedHexB != null) {
        int dist = axialDistance(selectedHexA!, selectedHexB!);
        distanceInfoSpan.text = '$dist hexes';
        lineAtoB = axialLineDraw(selectedHexA!, selectedHexB!);
    } else {
        distanceInfoSpan.text = '-';
        lineAtoB.clear();
    }

    if (selectedHexA == null) {
        instructionTextSpan.text = 'Click on the grid to select the first hex (A).';
    } else if (selectedHexB == null) {
        instructionTextSpan.text = 'First hex (A) selected. Click to select second hex (B) or click A to deselect.';
    } else {
        instructionTextSpan.text = 'Both hexes selected. Click Reset to start over.';
    }
    redrawCanvas();
}

void handleCanvasClick(MouseEvent event) {
    final rect = canvas.getBoundingClientRect();
    final mousePos = Point((event.client.x - rect.left).toDouble(), (event.client.y - rect.top).toDouble());
    Axial clickedAxial = pixelToAxial(mousePos);

    if (selectedHexA == null) {
        selectedHexA = clickedAxial;
    } else if (selectedHexB == null) {
        if (clickedAxial == selectedHexA) { // Clicked A again
            selectedHexA = null; // Deselect A
        } else {
            selectedHexB = clickedAxial;
        }
    } else {
        // Both A and B are selected, clicking does nothing until reset
        // Or, we could interpret a click as starting a new selection for A
        // For now, require reset.
    }
    updateInfoPanel();
}

void resetSelection() {
    selectedHexA = null;
    selectedHexB = null;
    updateInfoPanel();
}

void main() {
    canvas = querySelector('#hexInteractionCanvas') as CanvasElement;
    ctx = canvas.getContext('2d') as CanvasRenderingContext2D;

    resetButton = querySelector('#resetButton') as ButtonElement;
    instructionTextSpan = querySelector('#instructionText') as SpanElement;
    hexACoordsSpan = querySelector('#hexA_coords') as SpanElement;
    hexBCoordsSpan = querySelector('#hexB_coords') as SpanElement;
    hexANeighborsInfoSpan = querySelector('#hexA_neighbors_info') as SpanElement;
    distanceInfoSpan = querySelector('#distance_info') as SpanElement;

    resetButton.onClick.listen((_) => resetSelection());
    canvas.onClick.listen(handleCanvasClick);

    // Initial setup
    resetSelection(); // This also calls updateInfoPanel which calls redrawCanvas
}
