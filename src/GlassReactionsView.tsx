import type { ColorValue, ViewProps } from 'react-native';

type Props = ViewProps & {
  color?: ColorValue;
};

export function GlassReactionsView(_props: Props): never {
  throw new Error(
    "'react-native-glass-reactions' is only supported on native platforms."
  );
}
