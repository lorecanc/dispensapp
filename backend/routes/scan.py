from fastapi import APIRouter
from fastapi.responses import JSONResponse

from backend.schemas import MessageResponse, ScanRequest, ScanResponse
from backend.services.off import fetch_product

router = APIRouter(prefix="/api", tags=["scan"])


@router.post("/scan", response_model=ScanResponse)
async def scan_barcode(body: ScanRequest):
    result = await fetch_product(body.barcode)

    if result is None:
        return JSONResponse(
            status_code=502,
            content=MessageResponse(
                message="Errore durante la comunicazione con Open Food Facts"
            ).model_dump(),
        )

    if not result.get("name"):
        return ScanResponse(
            found=False,
            barcode=body.barcode,
            message="Prodotto non trovato nel database Open Food Facts",
        )

    return ScanResponse(
        found=True,
        barcode=result["barcode"],
        name=result["name"],
        brand=result.get("brand"),
        categories=result.get("categories", []),
        image_url=result.get("image_url"),
    )
