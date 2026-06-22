import { Stack } from "expo-router";

export default function TabsLayout() {
  return (
    <Stack
      screenOptions={{
        headerLargeTitle: true,
        headerTransparent: false,
      }}
    >
      <Stack.Screen
        name="index"
        options={{ title: "Dispensa", headerLargeTitle: true }}
      />
      <Stack.Screen
        name="scanner"
        options={{ presentation: "modal", headerShown: false }}
      />
      <Stack.Screen
        name="product/[barcode]"
        options={{ title: "Dettaglio Prodotto" }}
      />
      <Stack.Screen
        name="manual"
        options={{ title: "Inserimento Manuale", presentation: "modal" }}
      />
      <Stack.Screen name="export" options={{ title: "Esporta" }} />
    </Stack>
  );
}
