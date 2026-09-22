import Foundation

enum GazeCompanionShader {
	static let source = #"""
#include <metal_stdlib>
using namespace metal;

struct FaceUniforms {
    float4 pose;
    float4 expression;
    float4 transform;
    float4 viewport;
};

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

vertex VertexOut faceVertex(uint index [[vertex_id]]) {
    float2 positions[] = {float2(-1, -1), float2(3, -1), float2(-1, 3)};
    VertexOut output;
    output.position = float4(positions[index], 0, 1);
    output.uv = positions[index];
    return output;
}

float2 rotatePlane(float2 point, float angle) {
    float cosine = cos(angle), sine = sin(angle);
    return float2(cosine * point.x - sine * point.y, sine * point.x + cosine * point.y);
}

float3 localPoint(float3 point, constant FaceUniforms &uniforms) {
    point.x -= uniforms.transform.w * 2.2;
    point.y += uniforms.transform.z * 2.2;
    point.xy = rotatePlane(point.xy, -(uniforms.transform.x - 3) * M_PI_F / 180);
    point.yz = rotatePlane(point.yz, -uniforms.pose.y * 0.384);
    point.xz = rotatePlane(point.xz, uniforms.pose.x * 0.489 - uniforms.viewport.z);
    point.xy /= float2(1 - uniforms.transform.y * 0.5, 1 + uniforms.transform.y);
    return point;
}

float bodyDistance(float3 point) {
    float2 plane = abs(point.xy);
    float radial = pow(pow(plane.x, 3.5) + pow(plane.y, 3.5), 1.0 / 3.5);
    float volume = pow(pow(radial / 0.88, 4.0) + pow(abs(point.z) / 0.68, 4.0), 0.25);
    return (volume - 1.0) * 0.60;
}

float worldDistance(float3 point, constant FaceUniforms &uniforms) {
    return bodyDistance(localPoint(point, uniforms)) * 0.85;
}

float3 surfaceNormal(float3 point, constant FaceUniforms &uniforms) {
    const float epsilon = 0.001;
    return normalize(float3(
        worldDistance(point + float3(epsilon, 0, 0), uniforms) - worldDistance(point - float3(epsilon, 0, 0), uniforms),
        worldDistance(point + float3(0, epsilon, 0), uniforms) - worldDistance(point - float3(0, epsilon, 0), uniforms),
        worldDistance(point + float3(0, 0, epsilon), uniforms) - worldDistance(point - float3(0, 0, epsilon), uniforms)));
}

float segmentDistance(float2 point, float2 start, float2 end) {
    float2 segment = end - start;
    float amount = clamp(dot(point - start, segment) / max(dot(segment, segment), 0.000001), 0.0, 1.0);
    return length(point - start - amount * segment);
}

float eyeDistance(float2 point, float sadness, float eyesOpen, float side) {
    point = rotatePlane(point, side * sadness * 0.16);
    point.y /= max(0.09, eyesOpen);
    float distance = 10;
    float2 previous;
    for (int index = 0; index <= 10; index++) {
        float fraction = float(index) / 5 - 1;
        float2 current = float2(0, fraction * (0.110 - sadness * 0.022));
        if (index > 0) distance = min(distance, segmentDistance(point, previous, current));
        previous = current;
    }
    return distance - 0.110;
}

float mouthDistance(float2 point, float expression, float mouthOpen) {
    if (mouthOpen > 0.001) {
        float2 scaled = point / float2(0.065 + mouthOpen * 0.045, 0.014 + mouthOpen * 0.125);
        return (length(scaled) - 1) * 0.09;
    }
    float distance = 10;
    float2 previous;
    for (int index = 0; index <= 14; index++) {
        float fraction = float(index) / 7 - 1;
        float2 current = float2(fraction * 0.138, -expression * 0.065 * (1 - fraction * fraction));
        if (index > 0) distance = min(distance, segmentDistance(point, previous, current));
        previous = current;
    }
    return distance - mix(0.034, 0.044, clamp(expression, 0.0, 1.0));
}

float4 facePixel(float2 uv, constant FaceUniforms &uniforms) {
    uv.x *= uniforms.viewport.x / uniforms.viewport.y;
    float3 origin = float3(0, 0, 5.2);
    float3 direction = normalize(float3(uv * 1.24, -5.2));
    float travel = 3.6;
    float3 position;
    bool hit = false;
    for (int step = 0; step < 48; step++) {
        position = origin + direction * travel;
        float distance = worldDistance(position, uniforms);
        if (distance < 0.0007) { hit = true; break; }
        travel += distance;
        if (travel > 6.6) break;
    }
    if (!hit) return float4(0);
    float3 normal = surfaceNormal(position, uniforms);
    float3 local = localPoint(position, uniforms);
    float3 view = -direction;
    float3 keyLight = normalize(float3(-3.2, 4.8, 5.5) - position);
    float diffuse = max(0.0, dot(normal, keyLight));
    float3 halfway = normalize(keyLight + view);
    float broad = pow(max(dot(normal, halfway), 0.0), 18.0);
    float rim = pow(1 - max(dot(normal, view), 0.0), 3.0);
    float front = smoothstep(0.30, 0.58, local.z);
    float gradient = clamp((position.x - position.y + 1.6) / 3.2, 0.0, 1.0);
    float tone = gradient < 0.5 ? mix(0.30, 0.13, gradient * 2) : mix(0.13, 0.20, (gradient - 0.5) * 2);
    float wrap = 1 - pow(clamp(local.z / 0.68, 0.0, 1.0), 8.0);
    tone = mix(tone, 0.23, wrap * 0.65);
    float edge = exp(-pow(max(dot(normal, view), 0.0) / 0.22, 2.0));
    float stroke = gradient < 0.5 ? mix(0.09, 0.015, gradient * 2) : mix(0.015, 0.055, (gradient - 0.5) * 2);
    float2 gleamPoint = rotatePlane(local.xy - float2(-0.48, 0.54), -0.6);
    float gleam = exp(-dot(gleamPoint / float2(0.21, 0.095), gleamPoint / float2(0.21, 0.095))) * 0.12;
    float3 encoded = float3(tone + edge * stroke + gleam * front + broad * 0.035 + rim * diffuse * 0.025);
    float sadness = max(0.0, -uniforms.expression.x);
    float2 eyePoint = local.xy - float2(uniforms.expression.y * 0.176, -0.158);
    float left = eyeDistance(eyePoint + float2(0.242, 0), sadness, uniforms.pose.z, -1);
    float right = eyeDistance(eyePoint - float2(0.242, 0), sadness, uniforms.pose.z, 1);
    float featureDistance = min(left, right);
    float smileOffset = uniforms.pose.w > 0.001 ? 0.0 : 0.06 * clamp(uniforms.expression.x, 0.0, 1.0);
    float mouth = mouthDistance(local.xy - float2(0, -0.475 - smileOffset), uniforms.expression.x, uniforms.pose.w);
    float mouthVisibility = max(abs(uniforms.expression.x), uniforms.pose.w);
    float pixelWidth = 2.6 / uniforms.viewport.y;
    float eyes = 1 - smoothstep(-pixelWidth, pixelWidth, featureDistance);
    float smile = (1 - smoothstep(-pixelWidth, pixelWidth, mouth)) * mouthVisibility;
    float feature = max(eyes, smile) * front;
    float glow = exp(-max(0.0, featureDistance) * 55.0) * 0.008 * front;
    encoded += glow;
    float pearl = uniforms.expression.z;
    encoded = mix(encoded, float3(0.80) + encoded * 0.50, pearl);
    encoded *= uniforms.expression.w;
    encoded = mix(encoded, float3(mix(0.97, 0.10, pearl)), feature);
    float shellAlpha = clamp(uniforms.viewport.w + rim * 0.16, 0.0, 1.0);
    float alpha = mix(shellAlpha, 1.0, feature);
    return float4(encoded * alpha, alpha);
}

fragment float4 faceFragment(VertexOut input [[stage_in]], constant FaceUniforms &uniforms [[buffer(0)]]) {
    return facePixel(input.uv, uniforms);
}
"""#
}
