import { Image as ExpoImage } from "expo-image";
import { useCssElement } from "react-native-css";
import type { ComponentProps } from "react";

type ImageProps = ComponentProps<typeof ExpoImage> & { className?: string };

function Image(props: ImageProps) {
  const { className, style, objectFit, contentFit, ...rest } = props;
  // Map objectFit → contentFit for expo-image compatibility
  const resolvedContentFit = contentFit || objectFit || "cover";
  return useCssElement(ExpoImage, {
    ...rest,
    contentFit: resolvedContentFit as any,
  }, { className: className || "" });
}

export { Image };
