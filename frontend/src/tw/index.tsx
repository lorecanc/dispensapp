import {
  View as RNView,
  Text as RNText,
  ScrollView as RNScrollView,
  Pressable as RNPressable,
  TextInput as RNTextInput,
} from "react-native";
import { Link as RouterLink } from "expo-router";
import { useCssElement } from "react-native-css";
import type { ComponentProps } from "react";

type ViewProps = ComponentProps<typeof RNView> & { className?: string };
type TextProps = ComponentProps<typeof RNText> & { className?: string };
type ScrollViewProps = ComponentProps<typeof RNScrollView> & {
  className?: string;
};
type PressableProps = ComponentProps<typeof RNPressable> & { className?: string };
type TextInputProps = ComponentProps<typeof RNTextInput> & { className?: string };
type LinkProps = ComponentProps<typeof RouterLink> & { className?: string };

function View(props: ViewProps) {
  const { className, style, ...rest } = props;
  return useCssElement(RNView, rest, { className: className || "" });
}

function Text(props: TextProps) {
  const { className, style, ...rest } = props;
  return useCssElement(RNText, rest, { className: className || "" });
}

function ScrollView(props: ScrollViewProps) {
  const { className, style, ...rest } = props;
  return useCssElement(RNScrollView, rest, {
    className: className || "",
  }) as any;
}

function Pressable(props: PressableProps) {
  const { className, style, ...rest } = props;
  return useCssElement(RNPressable, rest, { className: className || "" });
}

function TextInput(props: TextInputProps) {
  const { className, style, ...rest } = props;
  return useCssElement(RNTextInput, rest, { className: className || "" });
}

const Link = Object.assign(
  (props: LinkProps) => {
    const { className, style, ...rest } = props;
    return useCssElement(RouterLink, rest, { className: className || "" });
  },
  {
    Trigger: RouterLink.Trigger,
    useSegments: RouterLink.useSegments,
    useFocus: RouterLink.useFocus,
    useHref: RouterLink.useHref,
    useLink: RouterLink.useLink,
    useRootNavigation: RouterLink.useRootNavigation,
  }
);

export { View, Text, ScrollView, Pressable, TextInput, Link };
