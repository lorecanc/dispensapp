import { View, Text } from "@/tw";

interface Props {
  title: string;
  message?: string;
}

export default function EmptyState({ title, message }: Props) {
  return (
    <View className="flex-1 items-center justify-center px-8 py-20">
      <Text className="text-6xl mb-4">📦</Text>
      <Text className="text-lg font-semibold text-gray-700 text-center">
        {title}
      </Text>
      {message ? (
        <Text className="text-sm text-gray-500 text-center mt-2">
          {message}
        </Text>
      ) : null}
    </View>
  );
}
