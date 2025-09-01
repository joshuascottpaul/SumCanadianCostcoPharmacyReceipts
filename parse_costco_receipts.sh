#!/bin/bash

# =============================================================================
# Costco Pharmacy Receipt PDF Parser
# copyright 2025 josh paul
# =============================================================================
# 
# PURPOSE:
# This script processes scanned PDFs containing Costco pharmacy receipts,
# extracts "Patient Pays" amounts using OCR, and calculates the total sum
# for insurance reimbursement submissions.
#
# TESTED ON: macOS
#
# DEPENDENCIES:
# - pdftoppm (from poppler-utils): brew install poppler
# - curl (usually pre-installed on macOS)
# - jq (JSON processor): brew install jq  
# - bc (calculator): usually pre-installed on macOS
# - OCR.space API account and API key: https://ocr.space/ocrapi
#
# INSTALLATION:
# 1. Install Homebrew (if not already installed):
#    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
#
# 2. Install required dependencies:
#    brew install poppler jq
#
# 3. Get OCR.space API key:
#    - Visit https://ocr.space/ocrapi
#    - Sign up for free account (500 requests/month)
#    - Replace "apikey" below with your actual API key
#
# HOW TO USE:
# 1. Save this script as 'parse_costco_receipts.sh'
# 2. Make it executable: chmod +x parse_costco_receipts.sh
# 3. Update the API_KEY variable below with your OCR.space API key
# 4. Run: ./parse_costco_receipts.sh your_receipt.pdf
#
# EXAMPLE:
# ./parse_costco_receipts.sh costco_pharmacy_receipts_jan2025.pdf
#
# OUTPUT:
# The script will:
# - Convert each PDF page to PNG images
# - Process each image through OCR
# - Extract "Patient Pays" amounts
# - Display running total
# - Clean up temporary files
#
# =============================================================================

# Check if a PDF filename is provided
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <pdf_file>"
    echo "Example: $0 costco_receipts.pdf"
    exit 1
fi

PDF_FILE="$1"
PREFIX="scanned_page"

# Validate PDF file exists
if [ ! -f "$PDF_FILE" ]; then
    echo "Error: PDF file '$PDF_FILE' not found"
    exit 1
fi

# Check for required dependencies
command -v pdftoppm >/dev/null 2>&1 || {
    echo "Error: pdftoppm not found. Install with: brew install poppler"
    exit 1
}

command -v jq >/dev/null 2>&1 || {
    echo "Error: jq not found. Install with: brew install jq"
    exit 1
}

command -v bc >/dev/null 2>&1 || {
    echo "Error: bc not found. This should be pre-installed on macOS."
    exit 1
}

command -v curl >/dev/null 2>&1 || {
    echo "Error: curl not found. This should be pre-installed on macOS."
    exit 1
}

# Convert PDF to images (one per page)
echo "Converting PDF pages to images..."
pdftoppm -png "$PDF_FILE" "$PREFIX"

# Check if conversion was successful
if [ ! -f "${PREFIX}-1.png" ]; then
    echo "Error: PDF conversion failed. Check if the PDF file is valid."
    exit 1
fi

# API endpoint for OCR.space
OCR_API_URL="https://api.ocr.space/parse/image"
# TODO: Replace with your actual OCR.space API key
API_KEY="apikey"  # Get your free key at https://ocr.space/ocrapi

if [ "$API_KEY" = "apikey" ]; then
    echo "Warning: Please update the API_KEY variable with your OCR.space API key"
    echo "Get a free key at: https://ocr.space/ocrapi"
fi

total=0
receipt_count=0

# Loop through each page image
for page in "$PREFIX"-*.png; do
    if [ -f "$page" ]; then
        echo "Processing $page..."
        receipt_count=$((receipt_count + 1))
        
        # Send the image to the OCR API
        response=$(curl -s -X POST "$OCR_API_URL" \
            -H "apikey: $API_KEY" \
            -F "file=@$page" \
            -F "language=eng" \
            -F "OCREngine=2")
        
        # Check if API call was successful
        if [ $? -ne 0 ]; then
            echo "Error: Failed to process $page with OCR API"
            continue
        fi
        
        # Extract the "Patient Pays" amount using jq
        # This looks for the pattern "Patient Pays: $XX.XX" in the OCR text
        amount=$(echo "$response" | jq -r '.ParsedResults[0].ParsedText | capture("Patient Pays: \\$?(?<amount>[0-9]+\\.?[0-9]*)"; "i").amount // empty')
        
        if [ -n "$amount" ] && [ "$amount" != "null" ]; then
            echo "  ✓ Found Patient Pays amount: \$${amount}"
            total=$(echo "$total + $amount" | bc -l)
        else
            echo "  ✗ No 'Patient Pays' amount found in $page"
            # Optionally show OCR text for debugging
            # echo "OCR Text: $(echo "$response" | jq -r '.ParsedResults[0].ParsedText')"
        fi
    fi
done

# Print summary
echo ""
echo "============================================="
echo "SUMMARY"
echo "============================================="
echo "Pages processed: $receipt_count"
echo "Total 'Patient Pays' amount: \$$(printf "%.2f" "$total")"
echo ""
echo "💡 TIP: Save this amount for your insurance reimbursement claim"

# Clean up: remove temporary image files
echo "Cleaning up temporary files..."
rm -f "$PREFIX"-*.png

echo "Done!"
