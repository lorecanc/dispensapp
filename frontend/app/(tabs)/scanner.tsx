import { useState, useCallback } from "react";
import { ActivityIndicator, Alert, Linking } from "react-native";
import { useRouter } from "expo-router";
import { CameraView, useCameraPermissions } from "expo-camera";
import * as Haptics from "expo-haptics";
import { View, Text, Pressable } from "@/tw";
import { useScan } from "@/api/client";

export default function ScannerScreen() {
  const router = useRouter();
  const [permission, requestPermission] = useCameraPermissions();
  const [scanned, setScanned] = useState(false);
  const scanMutation = useScan();

  const handleScan = useCallback(
    async ({ data }: { data: string }) => {
      if (scanned || scanMutation.isPending) return;
      setScanned(true);

      try {
        const result = await scanMutation.mutateAsync({ barcode: data });

        if (result.found) {
          await Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success);
          const params = new URLSearchParams();
          if (result.name) params.set("name", result.name);
          if (result.brand) params.set("brand", result.brand);
          if (result.image_url) params.set("image_url", result.image_url);
          if (result.categories && result.categories.length > 0) {
            params.set("categories", JSON.stringify(result.categories));
          }
          router.replace(
            `/product/${encodeURIComponent(result.barcode)}?${params.toString()}`
          );
        } else {
          await Haptics.notificationAsync(Haptics.NotificationFeedbackType.Warning);
          router.replace(
            `/manual?barcode=${encodeURIComponent(result.barcode)}`
          );
        }
      } catch (err: any) {
        setScanned(false);
        Alert.alert(
          "Errore",
          err?.message ?? "Impossibile elaborare il codice a barre"
        );
      }
    },
    [scanned, scanMutation, router]
  );

  // Permission not yet determined — request UI
  if (!permission) {
    return (
      <View className="flex-1 items-center justify-center px-6">
        <ActivityIndicator size="large" color="#3b82f6" />
      </View>
    );
  }

  // Permission can be requested
  if (!permission.granted && permission.canAskAgain) {
    return (
      <View className="flex-1 items-center justify-center px-6">
        <Text className="text-lg font-semibold text-gray-800 mb-2">
          Autorizzazione Fotocamera
        </Text>
        <Text className="text-sm text-gray-500 text-center mb-6">
          Usiamo la fotocamera per scansionare i codici a barre dei prodotti.
        </Text>
        <Pressable
          onPress={requestPermission}
          className="bg-blue-500 px-6 py-2.5 rounded-xl"
        >
          <Text className="text-white font-semibold">Consenti</Text>
        </Pressable>
        <Pressable
          onPress={() => router.back()}
          className="mt-4 px-6 py-2.5"
        >
          <Text className="text-gray-500 font-semibold">Annulla</Text>
        </Pressable>
      </View>
    );
  }

  // Permission denied — can't ask again
  if (!permission.granted) {
    return (
      <View className="flex-1 items-center justify-center px-6">
        <Text className="text-lg font-semibold text-gray-800 mb-2">
          Fotocamera non disponibile
        </Text>
        <Text className="text-sm text-gray-500 text-center mb-6">
          Per scansionare i codici a barre, autorizza l'accesso alla fotocamera
          nelle impostazioni del dispositivo.
        </Text>
        <Pressable
          onPress={() => Linking.openSettings()}
          className="bg-blue-500 px-6 py-2.5 rounded-xl"
        >
          <Text className="text-white font-semibold">Apri Impostazioni</Text>
        </Pressable>
        <Pressable
          onPress={() => router.back()}
          className="mt-4 px-6 py-2.5"
        >
          <Text className="text-gray-500 font-semibold">Annulla</Text>
        </Pressable>
      </View>
    );
  }

  // Permission granted — show camera
  return (
    <View className="flex-1">
      <CameraView
        facing="back"
        barcodeScannerSettings={{
          barcodeTypes: [
            "ean13",
            "ean8",
            "upc_a",
            "upc_e",
            "code128",
            "code39",
            "qr",
          ],
        }}
        onBarcodeScanned={handleScan}
        style={{ flex: 1 }}
      >
        {/* Loading overlay during scan */}
        {scanMutation.isPending && (
          <View className="absolute inset-0 bg-black/50 items-center justify-center">
            <ActivityIndicator size="large" color="white" />
            <Text className="text-white text-base mt-3 font-semibold">
              Ricerca prodotto...
            </Text>
          </View>
        )}
      </CameraView>

      {/* Footer button */}
      <View className="absolute bottom-10 left-0 right-0 items-center">
        <Pressable
          onPress={() => router.push("/manual")}
          className="bg-white/90 px-6 py-3 rounded-full shadow-lg"
        >
          <Text className="text-blue-600 font-semibold text-base">
            Inserimento manuale
          </Text>
        </Pressable>
      </View>
    </View>
  );
}
