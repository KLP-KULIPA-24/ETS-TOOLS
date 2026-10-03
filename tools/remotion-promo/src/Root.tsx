import React from "react";
import { Composition } from "remotion";
import { Promo, TOTAL_FRAMES, FPS } from "./Promo";

export const RemotionRoot: React.FC = () => {
  return (
    <Composition
      id="Promo"
      component={Promo}
      durationInFrames={TOTAL_FRAMES}
      fps={FPS}
      width={1920}
      height={1080}
    />
  );
};
