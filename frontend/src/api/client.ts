import {
  useMutation,
  useQuery,
  useQueryClient,
  QueryClient,
} from "@tanstack/react-query";
import type {
  ScanRequest,
  ScanResponse,
  InventoryCreate,
  InventoryCreateManual,
  InventoryOut,
  ApiError,
} from "./types";

const BASE_URL = process.env.EXPO_PUBLIC_API_URL ?? "http://localhost:8000";

export const queryClient = new QueryClient();

async function apiFetch<T>(
  path: string,
  init?: RequestInit,
  rawText?: boolean
): Promise<T> {
  const url = `${BASE_URL}${path}`;
  const res = await fetch(url, {
    headers: { "Content-Type": "application/json", ...init?.headers },
    ...init,
  });

  if (!res.ok) {
    let message = `Errore ${res.status}`;
    try {
      const body = await res.json();
      message = body.message ?? message;
    } catch {
      // ignore parse failure, use default message
    }
    throw { status: res.status, message } as ApiError;
  }

  if (rawText) {
    return (await res.text()) as unknown as T;
  }

  return res.json() as Promise<T>;
}

// --- React Query hooks ---

export function useInventory() {
  return useQuery<InventoryOut[]>({
    queryKey: ["inventory"],
    queryFn: () => apiFetch<InventoryOut[]>("/api/inventory"),
  });
}

export function useScan() {
  return useMutation<ScanResponse, ApiError, ScanRequest>({
    mutationKey: ["scan"],
    mutationFn: (body) =>
      apiFetch<ScanResponse>("/api/scan", {
        method: "POST",
        body: JSON.stringify(body),
      }),
  });
}

export function useAddInventory() {
  const client = useQueryClient();
  return useMutation<InventoryOut, ApiError, InventoryCreate>({
    mutationKey: ["add-inventory"],
    mutationFn: (body) =>
      apiFetch<InventoryOut>("/api/inventory", {
        method: "POST",
        body: JSON.stringify(body),
      }),
    onSuccess: () => {
      client.invalidateQueries({ queryKey: ["inventory"] });
    },
  });
}

export function useAddManual() {
  const client = useQueryClient();
  return useMutation<InventoryOut, ApiError, InventoryCreateManual>({
    mutationKey: ["add-manual"],
    mutationFn: (body) =>
      apiFetch<InventoryOut>("/api/inventory/manual", {
        method: "POST",
        body: JSON.stringify(body),
      }),
    onSuccess: () => {
      client.invalidateQueries({ queryKey: ["inventory"] });
    },
  });
}

export function useExportMarkdown() {
  return useQuery<string>({
    queryKey: ["export"],
    queryFn: () =>
      apiFetch<string>("/api/inventory/export", undefined, true),
    staleTime: 0,
  });
}
