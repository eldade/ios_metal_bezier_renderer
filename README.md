# High-performance Bezier Curves in the GPU with Metal
Lately I've been experimenting with high-performance 2D graphics on iOS using Metal. It's interesting in that tasks that used to be supported by the fixed hardware in the older graphics processors, have become a bit more challenging and less of a natural fit for today's modern GPU hardware.

![iPad Screenshot with thousands of Bezier curves rendered in realtime](Screenshot.png)

In this project I spent some time playing with rendering Bezier curves completely in the GPU and measuring the kind of performance that can be achieved. Other OpenGL implementations I was able to find online appeared to be cheating: They were actually calculating the vertices on the CPU and feeding the calculated data to the GPU, so all the GPU was doing was actually drawing the triangles to the screen.

In this implementation the Bezier curve is calculated in the vertex shader, which achieves very high performance.

## Visualizing the triangles
As with any GPU-based rendering, we use triangles to actually render our curves, which significantly complicates the vertex shader and adds cost. We could use simple lines and just have each vertex shader calculate a single point, but then all we'd get is a fixed-width curve. Instead, we compute triangles out of the curve and render those.

![Visualizing the triangles](Wireframe Screenshot.png)
