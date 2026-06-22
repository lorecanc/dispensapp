import { View, Text, Pressable } from "@/tw";
import { Image } from "@/tw/image";
import StatusBadge from "./status-badge";
import { useRouter } from "expo-router";
import type { InventoryOut } from "@/api/types";

interface Props {
  item: InventoryOut;
}

function formatDate(dateStr?: string): string {
  if (!dateStr) return "—";
  const d = new Date(dateStr);
  const day = String(d.getDate()).padStart(2, "0");
  const month = String(d.getMonth() + 1).padStart(2, "0");
  const year = d.getFullYear();
  return `${day}/${month}/${year}`;
}

export default function ProductCard({ item }: Props) {
  const router = useRouter();

  function handlePress() {
    const params = new URLSearchParams();
    if (item.name) params.set("name", item.name);
    if (item.brand) params.set("brand", item.brand);
    if (item.image_url) params.set("image_url", item.image_url);
    if (item.category) params.set("categories", JSON.stringify([item.category]));
    router.push(`/product/${item.barcode}?${params.toString()}`);
  }

  return (
    <Pressable
      onPress={handlePress}
      className="flex-row items-center px-4 py-3 border-b border-gray-200 active:bg-gray-50"
    >
      {item.image_url ? (
        <Image
          source={{ uri: item.image_url }}
          className="w-12 h-12 rounded-lg mr-3"
          objectFit="cover"
        />
      ) : (
        <View className="w-12 h-12 rounded-lg bg-gray-200 mr-3 items-center justify-center">
          <Text className="text-xl">📦</Text>
        </View>
      )}

      <View className="flex-1 mr-3">
        <Text className="text-base font-semibold text-gray-900" numberOfLines={1}>
          {item.name}
        </Text>
        {item.brand ? (
          <Text className="text-sm text-gray-500" numberOfLines={1}>
            {item.brand}
          </Text>
        ) : null}
        <Text className="text-xs text-gray-400 mt-0.5">
          Scadenza: {formatDate(item.expiration_date)}
        </Text>
      </View>

      <StatusBadge status={item.status} />
    </Pressable>
  );
}
