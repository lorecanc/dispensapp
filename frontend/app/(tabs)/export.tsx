import { ActivityIndicator, Alert } from "react-native";
import { useRouter } from "expo-router";
import * as FileSystem from "expo-file-system";
import * as Sharing from "expo-sharing";
import { View, Text, ScrollView, Pressable } from "@/tw";
import { useExportMarkdown } from "@/api/client";

export default function ExportScreen() {
  const router = useRouter();
  const { data: markdown, isLoading, error, refetch } = useExportMarkdown();

  async function handleShare() {
    if (!markdown) return;

    try {
      const filename = `inventario-${new Date().toISOString().slice(0, 10)}.md`;
      const fileUri = FileSystem.cacheDirectory + filename;
      await FileSystem.writeAsStringAsync(fileUri, markdown, {
        encoding: FileSystem.EncodingType.UTF8,
      });

      await Sharing.shareAsync(fileUri, {
        mimeType: "text/markdown",
        dialogTitle: "Esporta Inventario",
      });
    } catch (err: any) {
      Alert.alert("Errore", err?.message ?? "Impossibile condividere il file");
    }
  }

  return (
    <ScrollView contentInsetAdjustmentBehavior="automatic" className="flex-1 bg-white">
      <View className="p-4">
        {isLoading ? (
          <View className="items-center justify-center py-20">
            <ActivityIndicator size="large" color="#3b82f6" />
            <Text className="text-gray-500 mt-3">Caricamento...</Text>
          </View>
        ) : error ? (
          <View className="items-center justify-center py-20 px-6">
            <Text className="text-base text-red-600 text-center mb-4">
              {error?.message ?? "Errore durante il caricamento"}
            </Text>
            <Pressable
              onPress={() => refetch()}
              className="bg-blue-500 px-6 py-2.5 rounded-xl"
            >
              <Text className="text-white font-semibold">Riprova</Text>
            </Pressable>
          </View>
        ) : (
          <>
            {/* Markdown preview */}
            <View className="bg-gray-50 rounded-xl p-4 mb-6">
              <Text
                className="text-sm font-mono text-gray-800 leading-relaxed"
                selectable
              >
                {markdown}
              </Text>
            </View>

            {/* Share button */}
            <Pressable
              onPress={handleShare}
              className="bg-blue-500 rounded-xl py-3.5 items-center mb-3"
            >
              <Text className="text-white font-semibold text-base">
                Condividi
              </Text>
            </Pressable>

            {/* Back to pantry */}
            <Pressable
              onPress={() => router.replace("/")}
              className="bg-gray-200 rounded-xl py-3.5 items-center"
            >
              <Text className="text-gray-700 font-semibold text-base">
                Torna alla dispensa
              </Text>
            </Pressable>
          </>
        )}
      </View>
    </ScrollView>
  );
}
