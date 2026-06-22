import { View, Text } from "@/tw";
import type { InventoryStatus } from "@/api/types";

const statusConfig: Record<
  InventoryStatus,
  { bg: string; text: string; label: string }
> = {
  expired: {
    bg: "bg-red-100",
    text: "text-red-800",
    label: "🔴 Scaduto",
  },
  expiring_soon: {
    bg: "bg-amber-100",
    text: "text-amber-800",
    label: "🟡 In scadenza",
  },
  ok: {
    bg: "bg-emerald-100",
    text: "text-emerald-800",
    label: "🟢 OK",
  },
};

interface Props {
  status: InventoryStatus;
}

export default function StatusBadge({ status }: Props) {
  const cfg = statusConfig[status] ?? statusConfig.ok;
  return (
    <View className={`px-2.5 py-1 rounded-full ${cfg.bg}`}>
      <Text className={`text-xs font-semibold ${cfg.text}`}>{cfg.label}</Text>
    </View>
  );
}
