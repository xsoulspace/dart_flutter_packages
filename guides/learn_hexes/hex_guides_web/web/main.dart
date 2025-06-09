import 'dart:html';
import 'dart:math';
import 'package:hex_guides_web/hex.dart';
import 'package:hex_guides_web/axial.dart';
import 'package:hex_guides_web/offset.dart' as offset_coord_system;
import 'package:hex_guides_web/conversions.dart';
import 'package:hex_guides_web/hex_algorithms.dart';

late CanvasElement canvas;
late CanvasRenderingContext2D ctx;
late DivElement infoPanel; // Made late
late SpanElement pixelCoordsSpan, cubeCoordsSpan, axialCoordsSpan, offsetCoordsSpan; // Made late

// Grid display settings
double hexSize = 30.0;
bool isPointyTop = true;
offset_coord_system.OffsetCoordType currentOffsetType = offset_coord_system.OffsetCoordType.oddR;

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
    double s = -q - r;
    Hex roundedCube = cubeRound(q, r, s);
    return cubeToAxial(roundedCube);
}

void drawHex(Axial axial, {String? label, String fillStyle = '#cccccc'}) {
    Point<double> center = hexToPixel(axial);
    ctx.beginPath();
    for (int i = 0; i < 6; i++) {
        double angle = 2 * pi / 6 * (i + (isPointyTop ? 0.5 : 0));
        double x = center.x + hexSize * cos(angle);
        double y = center.y + hexSize * sin(angle);
        if (i == 0) {
            ctx.moveTo(x, y);
        } else {
            ctx.lineTo(x, y);
        }
    }
    ctx.closePath();
    ctx.fillStyle = fillStyle;
    ctx.fill();
    ctx.stroke();

    if (label != null) {
        ctx.fillStyle = 'black';
        ctx.font = '10px sans-serif';
        ctx.textAlign = 'center';
        ctx.textBaseline = 'middle';
        ctx.fillText(label, center.x, center.y);
    }
}

void drawGrid() {
    ctx.clearRect(0, 0, canvas.width!, canvas.height!);
    int range = (canvas.width! / (hexSize * (isPointyTop ? sqrt(3) : 1.5))) ~/ 2 + 1;
    for (int q = -range; q <= range; q++) {
        for (int r = max(-range, -q - range); r <= min(range, -q + range); r++) {
            drawHex(Axial(q,r));
        }
    }
}

void updateInfoPanel(Point<double> mousePos) {
    pixelCoordsSpan.text = '${mousePos.x.toStringAsFixed(2)}, ${mousePos.y.toStringAsFixed(2)}';
    Axial axial = pixelToAxial(mousePos);
    Hex cube = axialToCube(axial);
    axialCoordsSpan.text = 'q:${axial.q}, r:${axial.r}';
    cubeCoordsSpan.text = 'q:${cube.q}, r:${cube.r}, s:${cube.s}';
    offset_coord_system.OffsetCoord offset;
    switch (currentOffsetType) {
        case offset_coord_system.OffsetCoordType.oddR:
            offset = axialToOddROffset(axial);
            break;
        case offset_coord_system.OffsetCoordType.evenR:
            offset = axialToEvenROffset(axial);
            break;
        case offset_coord_system.OffsetCoordType.oddQ:
            offset = axialToOddQOffset(axial);
            break;
        case offset_coord_system.OffsetCoordType.evenQ:
            offset = axialToEvenQOffset(axial);
            break;
    }
    offsetCoordsSpan.text = 'col:${offset.col}, row:${offset.row} (Type: ${currentOffsetType.toString().split(".").last})';
    drawGrid();
    drawHex(axial, fillStyle: 'rgba(255, 0, 0, 0.3)');
}

void main() {
    canvas = querySelector('#hexCanvas') as CanvasElement;
    ctx = canvas.getContext('2d') as CanvasRenderingContext2D;
    infoPanel = querySelector('#infoPanel') as DivElement;
    pixelCoordsSpan = querySelector('#pixelCoords') as SpanElement;
    cubeCoordsSpan = querySelector('#cubeCoords') as SpanElement;
    axialCoordsSpan = querySelector('#axialCoords') as SpanElement;
    offsetCoordsSpan = querySelector('#offsetCoords') as SpanElement;

    final pointyTopRadio = querySelector('#pointyTop') as InputElement;
    final flatTopRadio = querySelector('#flatTop') as InputElement;
    final offsetTypeSelect = querySelector('#offsetType') as SelectElement;

    void updateGridSettings() {
        isPointyTop = pointyTopRadio.checked ?? true;
        String selectedOffset = offsetTypeSelect.value!;
        switch (selectedOffset) {
            case 'odd-r': currentOffsetType = offset_coord_system.OffsetCoordType.oddR; break;
            case 'even-r': currentOffsetType = offset_coord_system.OffsetCoordType.evenR; break;
            case 'odd-q': currentOffsetType = offset_coord_system.OffsetCoordType.oddQ; break;
            case 'even-q': currentOffsetType = offset_coord_system.OffsetCoordType.evenQ; break;
        }
        drawGrid();
    }

    pointyTopRadio.onChange.listen((_) => updateGridSettings());
    flatTopRadio.onChange.listen((_) => updateGridSettings());
    offsetTypeSelect.onChange.listen((_) => updateGridSettings());

    canvas.onMouseMove.listen((MouseEvent event) {
        final rect = canvas.getBoundingClientRect();
        // Ensure Point<double> is created by converting the result of subtraction to double
        final mousePos = Point<double>(
            (event.client.x - rect.left).toDouble(),
            (event.client.y - rect.top).toDouble()
        );
        updateInfoPanel(mousePos);
    });

    updateGridSettings();
}
