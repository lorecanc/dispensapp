export interface ScanRequest {
  barcode: string;
}

export interface ScanResponse {
  barcode: string;
  name?: string;
  brand?: string;
  categories: string[];
  image_url?: string;
  found: boolean;
  message?: string;
}

export interface InventoryCreate {
  barcode: string;
  name: string;
  brand?: string;
  expiration_date?: string;
  category?: string;
  image_url?: string;
}

export interface InventoryCreateManual {
  name: string;
  brand?: string;
  expiration_date?: string;
  category?: string;
}

export type InventoryStatus = "ok" | "expiring_soon" | "expired";

export interface InventoryOut {
  id: number;
  barcode?: string;
  name: string;
  brand?: string;
  expiration_date?: string;
  is_estimated: boolean;
  category?: string;
  image_url?: string;
  created_at: string;
  status: InventoryStatus;
}

export interface MessageResponse {
  message: string;
}

export interface ApiError {
  status: number;
  message: string;
}
