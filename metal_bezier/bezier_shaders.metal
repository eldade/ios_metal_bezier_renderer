//MIT License
//
//Copyright (c) 2016
//
//Permission is hereby granted, free of charge, to any person obtaining a copy
//of this software and associated documentation files (the "Software"), to deal
//in the Software without restriction, including without limitation the rights
//to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//copies of the Software, and to permit persons to whom the Software is
//furnished to do so, subject to the following conditions:
//
//The above copyright notice and this permission notice shall be included in all
//copies or substantial portions of the Software.
//
//THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//SOFTWARE.


#include <metal_stdlib>
#include <metal_texture>


using namespace metal;

struct GlobalParameters
{
    uint elementsPerInstance;
};

// BezierParameters represent a per-curve buffer specifying curve parameters. Note that
// even though the vertex shader is obviously called per-vertex, it actually uses the same
// BezierParameters instance (identified through the instance_id) for all vertexes in a given
// curve.
struct BezierParameters
{
    float2 a;
    float2 b;
    float2 p1;
    float2 p2;
    float lineThickness;
    float4 color;
    // The following vectors are used internally on the CPU-side. Since we're sharing memory
    // I do not believe this matters much performance-wise, and storing it in this struct
    // makes the code simpler on the CPU side. Though it is a recipe for disaster if someone
    // changes things without updating this.
    float2 unused[4];
    float unused2;
};

struct VertexOut {
    float4 pos[[position]];
    float4 color;
};

vertex VertexOut bezier_vertex(constant BezierParameters *allParams[[buffer(0)]],
                               constant GlobalParameters& globalParams[[buffer(1)]],
                               uint vertexId [[vertex_id]],
                               uint instanceId [[instance_id]])
{
    // TO DO: Is there no way to ask Metal to give us vertexes per instances?
    float t = (float) vertexId / globalParams.elementsPerInstance;
    
    BezierParameters params = allParams[instanceId];
    
    // This is a little trick to avoid conditional code. We need to determine which side of the
    // triangle we are processing, so as to calculate the correct "side" of the curve, so we just
    // check for odd vs. even vertexId values to determine that:
    float lineWidth = (1 - (((float) (vertexId % 2)) * 2.0)) * params.lineThickness;
    
    float2 a = params.a;
    float2 b = params.b;
    
    // We premultiply several values though I doubt it actually does anything performance-wise:
    float2 p1 = params.p1 * 3.0;
    float2 p2 = params.p2 * 3.0;
    
    float nt = 1.0f - t;

    float nt_2 = nt * nt;
    float nt_3 = nt_2 * nt;
    
    float t_2 = t * t;
    float t_3 = t_2 * t;

    // Calculate a single point in this Bezier curve:
    float2 point = a * nt_3 + p1 * nt_2 * t + p2 * nt * t_2 + b * t_3;
    
    // Calculate the tangent so we can produce a triangle (to achieve a line width greater than 1):
    float2 tangent = -3.0 * a * nt_2 + p1 * (1.0 - 4.0 * t + 3.0 * t_2) + p2 * (2.0 * t - 3.0 * t_2) + 3 * b * t_2;

    tangent = normalize(float2(-tangent.y, tangent.x));
    
    VertexOut vo;
    
    // Combine the point with the tangent and lineWidth to achieve a properly oriented
    // triangle for this point in the curve:
    vo.pos.xy = point + (tangent * (lineWidth / 2.0f));
    vo.pos.zw = float2(0, 1);
    vo.color = params.color;
    
    return vo;
}

fragment half4 bezier_fragment(VertexOut params[[stage_in]])
{
    return half4(params.color);
}

