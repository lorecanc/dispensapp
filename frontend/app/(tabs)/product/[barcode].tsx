import { useState } from "react";
import { ActivityIndicator, Alert } from "react-native";
import { useLocalSearchParams, useRouter } from "expo-router";
import * as Haptics from "expo-haptics";
import { View, Text, ScrollView, Pressable, TextInput } from "@/tw";
import { Image } from "@/tw/image";
import { useAddInventory } from "@/api/client";
import type { InventoryCreate } from "@/api/types";

export default function ProductDetailScreen() {
  const router = useRouter();
  const params = useLocalSearchParams<{
    barcode: string;
    name?: string;
    brand?: string;
    image_url?: string;
    categories?: string;
  }>();

  const [name, setName] = useState(params.name ?? "");
  const [brand, setBrand] = useState(params.brand ?? "");
  const [selectedCategory, setSelectedCategory] = useState<string | null>(null);
  const [autoCalculate, setAutoCalculate] = useState(true);
  const [manualDate, setManualDate] = useState("");

  const addMutation = useAddInventory();

  const rawCategories = params.categories
    ? (JSON.parse(params.categories) as string[]).filter(Boolean)
    : [];

  function handleSave() {
    if (!name.trim()) {
      Alert.alert("Errore", "Il nome del prodotto è obbligatorio");
      return;
    }

    const body: InventoryCreate = {
      barcode: params.barcode,
      name: name.trim(),
      brand: brand.trim() || undefined,
      category: selectedCategory ?? undefined,
      image_url: params.image_url || undefined,
    };

    if (!autoCalculate && manualDate.trim()) {
      body.expiration_date = manualDate.trim();
    }
    // If autoCalculate is on, omit expiration_date so server estimates

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
        {/* Product image */}
        {params.image_url ? (
          <View className="items-center mb-6">
            <Image
              source={{ uri: params.image_url }}
              className="w-48 h-48 rounded-2xl"
              objectFit="cover"
            />
          </View>
        ) : null}

        {/* Name and brand preview */}
        <Text className="text-2xl font-bold text-gray-900 mb-1">
          {name || "Prodotto"}
        </Text>
        {brand ? (
          <Text className="text-base text-gray-500 mb-4">{brand}</Text>
        ) : null}

        {/* OFF Categories as chips */}
        {rawCategories.length > 0 ? (
          <View className="mb-6">
            <Text className="text-sm font-semibold text-gray-700 mb-2">
              Categorie
            </Text>
            <View className="flex-row flex-wrap gap-2">
              {rawCategories.map((cat) => {
                const isSelected = selectedCategory === cat;
                return (
                  <Pressable
                    key={cat}
                    onPress={() =>
                      setSelectedCategory(isSelected ? null : cat)
                    }
                    className={`px-3 py-1.5 rounded-full border ${
                      isSelected
                        ? "bg-blue-500 border-blue-500"
                        : "bg-gray-100 border-gray-300"
                    }`}
                  >
                    <Text
                      className={`text-sm ${
                        isSelected ? "text-white" : "text-gray-700"
                      }`}
                    >
                      {cat}
                    </Text>
                  </Pressable>
                );
              })}
            </View>
          </View>
        ) : null}

        {/* Name input */}
        <View className="mb-4">
          <Text className="text-sm font-semibold text-gray-700 mb-1">Nome</Text>
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
                Data stimata in base alla categoria selezionata
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
