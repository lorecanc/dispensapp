import { useCallback } from "react";
import {
  ActivityIndicator,
  RefreshControl,
} from "react-native";
import { Stack } from "expo-router";
import * as Haptics from "expo-haptics";
import { View, Text, ScrollView, Pressable, Link } from "@/tw";
import { useInventory } from "@/api/client";
import ProductCard from "@/components/product-card";
import EmptyState from "@/components/empty-state";

export default function HomeScreen() {
  const { data: items, isLoading, error, refetch, isRefetching } = useInventory();

  const onRefresh = useCallback(() => {
    Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
    refetch();
  }, [refetch]);

  return (
    <>
      <Stack.Screen
        options={{
          title: "Dispensa",
          headerLargeTitle: true,
          headerRight: () => (
            <View className="flex-row gap-2 mr-2">
              <Link href="/export" className="text-blue-600 font-semibold text-base px-2 py-1">
                Esporta
              </Link>
              <Link href="/scanner" className="text-blue-600 font-semibold text-base px-2 py-1">
                Scanner
              </Link>
            </View>
          ),
        }}
      />

      {isLoading ? (
        <View className="flex-1 items-center justify-center">
          <ActivityIndicator size="large" color="#3b82f6" />
        </View>
      ) : error ? (
        <View className="flex-1 items-center justify-center px-6">
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
      ) : !items || items.length === 0 ? (
        <ScrollView
          contentInsetAdjustmentBehavior="automatic"
          refreshControl={
            <RefreshControl refreshing={isRefetching} onRefresh={onRefresh} />
          }
        >
          <EmptyState
            title="Nessun prodotto"
            message="Scansiona un codice a barre per iniziare"
          />
        </ScrollView>
      ) : (
        <ScrollView
          contentInsetAdjustmentBehavior="automatic"
          refreshControl={
            <RefreshControl refreshing={isRefetching} onRefresh={onRefresh} />
          }
        >
          <View className="py-1">
            {items.map((item) => (
              <ProductCard key={item.id} item={item} />
            ))}
          </View>
        </ScrollView>
      )}
    </>
  );
}
