//
//  File.metal
//  OnCue-OSX
//
//  Created by Jake Van Alstyne on 12/20/19.
//  Copyright © 2019 EggDevil. All rights reserved.
//

#include <metal_stdlib>
using namespace metal;

// Compute kernel
kernel void motionDetect(texture2d<half, access::read>  lastTexture  [[ texture(0) ]],
                         texture2d<half, access::read>  currentTexture  [[ texture(1) ]],
                         texture2d<half, access::write> outputTexture [[ texture(2) ]],
                         uint2 gid [[thread_position_in_grid]])
{
  // Don't read or write outside of the texture.
  if ((gid.x >= currentTexture.get_width()) || (gid.y >= currentTexture.get_height())) {
    return;
  }

//  const uint2 pixellatedGid = uint2((gid.x / 50) * 50, (gid.y / 50) * 50);
//
//  half4 lastInputColor = lastTexture.read(pixellatedGid);
//  half4 currentInputColor = currentTexture.read(pixellatedGid);

  half4 lastInputColor = lastTexture.read(gid);
  half4 currentInputColor = currentTexture.read(gid);

  half4 difference = half4(currentInputColor.r - lastInputColor.r,
                           currentInputColor.g - lastInputColor.g,
                           currentInputColor.b - lastInputColor.b,
                           1.0);
  float deltaDotP = dot(difference, difference);
  float red = 1.5 * (deltaDotP - 1.0);

  half4 outputColor =  deltaDotP > 1.2 ? half4(red, 0.0, 0.0, 1.0) : lastInputColor;

  outputTexture.write(outputColor, gid);
}
