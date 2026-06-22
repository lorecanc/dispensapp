import { useState } from "react";
import { ActivityIndicator, Alert } from "react-native";
import { useLocalSearchParams, useRouter } from "expo-router";
import * as Haptics from "expo-haptics";
import { View, Text, ScrollView, Pressable, TextInput } from "@/tw";
import { useAddManual } from "@/api/client";
import type { InventoryCreateManual } from "@/api/types";

export default function ManualEntryScreen() {
  const router = useRouter();
  const params = useLocalSearchParams<{
    barcode?: string;
    prefillName?: string;
  }>();

  const [name, setName] = useState(params.prefillName ?? "");
  const [brand, setBrand] = useState("");
  const [category, setCategory] = useState("");
  const [autoCalculate, setAutoCalculate] = useState(true);
  const [manualDate, setManualDate] = useState("");

  const addMutation = useAddManual();

  function handleSave() {
    if (!name.trim()) {
      Alert.alert("Errore", "Il nome del prodotto è obbligatorio");
      return;
    }

    const body: InventoryCreateManual = {
      name: name.trim(),
      brand: brand.trim() || undefined,
    };

    if (autoCalculate) {
      if (category.trim()) {
        body.category = category.trim();
        // Server will estimate expiration from category
      }
      // No expiration_date → server handles estimation logic
    } else {
      if (manualDate.trim()) {
        body.expiration_date = manualDate.trim();
      }
      body.category = category.trim() || undefined;
    }

    addMutation.mutate(body, {
      onSuccess: async () => {
        await Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success);
        router.replace("/");
      },
      onError: (err) => {
        Alert.alert("Errore", err.message ?? "Impossibile salvare il prodotto");
      },
    });
  }

  return (
    <ScrollView contentInsetAdjustmentBehavior="automatic" className="flex-1 bg-white">
      <View className="p-4">
        {/* Barcode info */}
        {params.barcode ? (
          <View className="bg-gray-100 rounded-xl px-4 py-3 mb-6">
            <Text className="text-sm text-gray-500">
              Codice: {params.barcode}
            </Text>
          </View>
        ) : null}

        {/* Name input */}
        <View className="mb-4">
          <Text className="text-sm font-semibold text-gray-700 mb-1">
            Nome <Text className="text-red-500">*</Text>
          </Text>
          <TextInput
            className="border border-gray-300 rounded-xl px-4 py-2.5 text-base"
            value={name}
            onChangeText={setName}
            placeholder="Nome prodotto"
          />
        </View>

        {/* Brand input */}
        <View className="mb-4">
          <Text className="text-sm font-semibold text-gray-700 mb-1">
            Marca
          </Text>
          <TextInput
            className="border border-gray-300 rounded-xl px-4 py-2.5 text-base"
            value={brand}
            onChangeText={setBrand}
            placeholder="Marca (opzionale)"
          />
        </View>

        {/* Category input */}
        <View className="mb-4">
          <Text className="text-sm font-semibold text-gray-700 mb-1">
            Categoria
          </Text>
          <TextInput
            className="border border-gray-300 rounded-xl px-4 py-2.5 text-base"
            value={category}
            onChangeText={setCategory}
            placeholder="es. pasta, latticini, verdura (opzionale)"
          />
        </View>

        {/* Expiration date section */}
        <View className="mb-6">
          <Pressable
            onPress={() => setAutoCalculate(!autoCalculate)}
            className="flex-row items-center mb-3"
          >
            <View
              className={`w-5 h-5 rounded border-2 mr-2 items-center justify-center ${
                autoCalculate
                  ? "bg-blue-500 border-blue-500"
                  : "border-gray-400"
              }`}
            >
              {autoCalculate ? (
                <Text className="text-white text-xs font-bold">✓</Text>
              ) : null}
            </View>
            <Text className="text-sm text-gray-700">
              📅 Calcola automaticamente
            </Text>
          </Pressable>

          {autoCalculate ? (
            <View className="bg-blue-50 rounded-xl px-4 py-3">
              <Text className="text-sm text-blue-700">
                Se inserisci una categoria, la scadenza verrà stimata
                automaticamente
              </Text>
            </View>
          ) : (
            <TextInput
              className="border border-gray-300 rounded-xl px-4 py-2.5 text-base"
              value={manualDate}
              onChangeText={setManualDate}
              placeholder="AAAA-MM-GG"
            />
          )}
        </View>

        {/* Save button */}
        <Pressable
          onPress={handleSave}
          disabled={addMutation.isPending}
          className="bg-blue-500 rounded-xl py-3.5 items-center disabled:opacity-50"
        >
          {addMutation.isPending ? (
            <ActivityIndicator color="white" />
          ) : (
            <Text className="text-white font-semibold text-base">Salva</Text>
          )}
        </Pressable>
      </View>
    </ScrollView>
  );
}
