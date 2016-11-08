//    Copyright (c) 2016, Eldad Eilam
//    All rights reserved.
//
//    Redistribution and use in source and binary forms, with or without modification, are
//    permitted provided that the following conditions are met:
//
//    1. Redistributions of source code must retain the above copyright notice, this list of
//       conditions and the following disclaimer.
//
//    2. Redistributions in binary form must reproduce the above copyright notice, this list
//       of conditions and the following disclaimer in the documentation and/or other materials
//       provided with the distribution.
//
//    3. Neither the name of the copyright holder nor the names of its contributors may be used
//       to endorse or promote products derived from this software without specific prior written
//       permission.
//
//    THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS
//    OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY
//    AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR
//    CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
//    DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
//    DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
//    WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN
//    ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.


#include <metal_stdlib>
#include <metal_texture>


using namespace metal;

struct GlobalParameters
{
    uint elementsPerInstance;
};

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
    // triangle we are producing, so as to calculate the correct "side" of the curve:
    float lineWidthCoef = 1 - (((float) (vertexId % 2)) * 2.0);
    
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
    vo.pos.xy = point + (tangent * (lineWidthCoef * params.lineThickness / 2.0f));
    vo.pos.zw = float2(0, 1);
    vo.color = params.color;
    
    return vo;
}

fragment half4 simple_fragment(VertexOut params[[stage_in]])
{
    return half4(params.color);
}

