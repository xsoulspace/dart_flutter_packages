# Interactive Hexagonal Grid Guides

This project provides a series of interactive web-based guides to help understand various concepts related to hexagonal grids. The content and algorithms are heavily based on the comprehensive [Hexagonal Grids article by Red Blob Games](https://www.redblobgames.com/grids/hexagons/).

These guides are designed to be hands-on, allowing you to see how different coordinate systems work, how algorithms behave, and how hex grids are used in practice.

## How to Run These Guides

To run these interactive guides locally on your machine:

1.  **Ensure Dart SDK is Installed:** If you don't have it, download and install the [Dart SDK](https://dart.dev/get-dart).
2.  **Activate `webdev`:** `webdev` is the tool used to build and serve web apps using Dart. Install or activate it globally:
    ```bash
    dart pub global activate webdev
    ```
3.  **Navigate to the Project Directory:** Open your terminal and navigate to this directory (`guides/learn_hexes/hex_guides_web/`).
4.  **Get Dependencies:** If this is the first time, or if `pubspec.yaml` changed, fetch the project dependencies:
    ```bash
    dart pub get
    ```
5.  **Serve the Guides:** Use `webdev` to compile and serve the guides:
    ```bash
    webdev serve
    ```
    This will typically make the guides available at `http://localhost:8080` (the port might vary). Open this URL in your web browser. The main page (`index.html`) will have links to all other guides.

## How to Study This Material (Suggested Order)

For those new to hexagonal grids, it's recommended to go through the guides in the following order. Each guide builds upon concepts introduced in earlier ones. Alongside each interactive guide, refer to the linked sections from Red Blob Games' article for deeper theoretical understanding.

1.  **[Main Page - Geometry & Coordinate Systems (`index.html`)]()**
    *   **Focus:** Basic hex shapes, pointy vs. flat tops, and an introduction to Cube, Axial, and Offset coordinate systems.
    *   **Red Blob Games Sections:**
        *   [Introduction](https://www.redblobgames.com/grids/hexagons/)
        *   [Geometry](https://www.redblobgames.com/grids/hexagons/#basics) (Size, Spacing, Angles)
        *   [Coordinate Systems Overview](https://www.redblobgames.com/grids/hexagons/#coordinates)
        *   [Offset Coordinates](https://www.redblobgames.com/grids/hexagons/#coordinates-offset)
        *   [Cube Coordinates](https://www.redblobgames.com/grids/hexagons/#coordinates-cube)
        *   [Axial Coordinates](https://www.redblobgames.com/grids/hexagons/#coordinates-axial)

2.  **[Coordinate Conversions (`guide_conversions.html`)]()**
    *   **Focus:** Interactively convert coordinates between Cube, Axial, and various Offset types.
    *   **Red Blob Games Section:** [Coordinate Conversion](https://www.redblobgames.com/grids/hexagons/#conversions)

3.  **[Neighbors & Distances (`guide_neighbors_distances.html`)]()**
    *   **Focus:** Identifying the 6 neighbors of a hex and calculating the grid distance between two hexes.
    *   **Red Blob Games Sections:**
        *   [Neighbors](https://www.redblobgames.com/grids/hexagons/#neighbors)
        *   [Distances](https://www.redblobgames.com/grids/hexagons/#distances)

4.  **[Line Drawing (`guide_line_drawing.html`)]()**
    *   **Focus:** Visualizing the line of hexes that connect two selected points.
    *   **Red Blob Games Section:** [Line Drawing](https://www.redblobgames.com/grids/hexagons/#line-drawing) (especially `cube_round` and `cube_lerp`)

5.  **[Hex↔Pixel Conversions (`guide_hex_pixel.html`)]()**
    *   **Focus:** Converting hex coordinates to screen pixel coordinates and vice-versa. Understand how hex size and orientation affect this.
    *   **Red Blob Games Sections:**
        *   [Hex to Pixel](https://www.redblobgames.com/grids/hexagons/#hex-to-pixel)
        *   [Pixel to Hex](https://www.redblobgames.com/grids/hexagons/#pixel-to-hex)
        *   [Rounding to Nearest Hex](https://www.redblobgames.com/grids/hexagons/#rounding) (critical for pixel-to-hex)

6.  **[Range & Field of View (`guide_range_fov.html`)]()**
    *   **Focus:** Determining hexes within a certain movement range and a basic interactive Field of View (FOV) demonstration.
    *   **Red Blob Games Sections:**
        *   [Movement Range](https://www.redblobgames.com/grids/hexagons/#range)
        *   [Field of View](https://www.redblobgames.com/grids/hexagons/#field-of-view) (Our guide is a simplified version)

7.  **[Rotation & Reflection (`guide_rotation_reflection.html`)]()**
    *   **Focus:** Rotating and reflecting a pattern of hexes around a central point.
    *   **Red Blob Games Sections:**
        *   [Rotation](https://www.redblobgames.com/grids/hexagons/#rotation)
        *   [Reflection](https://www.redblobgames.com/grids/hexagons/#reflection)

8.  **[Map Storage & Pathfinding (`guide_map_pathfinding.html`)]()**
    *   **Focus:** Illustrative concepts for storing hex map data and an interactive Breadth-First Search (BFS) pathfinding demo.
    *   **Red Blob Games Sections:**
        *   [Map Storage](https://www.redblobgames.com/grids/hexagons/#map-storage)
        *   [Pathfinding](https://www.redblobgames.com/grids/hexagons/#pathfinding) (Our guide uses BFS, the article discusses A* more broadly)

## Tips for Beginners

*   **Start with Cube Coordinates:** While they might seem unusual (using three axes for a 2D grid), many algorithms are simplest with Cube coordinates (q, r, s where q + r + s = 0). Axial coordinates (q, r) are a common storage format derived from Cube.
*   **Interactive Experimentation:** Use these guides to click around, change inputs, and observe the outcomes. Visual feedback is key.
*   **Read the Red Blob Games Article:** These guides are companions to, not replacements for, Amit Patel's excellent explanations. The article provides much more depth.
*   **Pointy vs. Flat Top:** Understand that hex grids can be oriented with hexes having pointy tops or flat tops. This affects coordinate calculations, especially for pixel conversions and some offset systems. Our guides mostly use pointy-top by default but some allow toggling.
*   **Don't Get Bogged Down by Offset Systems Initially:** Offset coordinates (odd-r, even-q, etc.) are common in many games but can be trickier for algorithms. Understand them, but perhaps focus on Axial/Cube for algorithmic thinking first.

Happy Hex Gridding!
