#!/bin/bash

# Default values for parameters
AGGREGATOR="http://127.0.0.1:9000"      # Set Aggregator URL
PUBLISHER="http://127.0.0.1:9001"       # Set Publisher URL

ENABLE_STRING_UPLOAD_PUBLISHER=true      # Set to false to disable string upload
ENABLE_FILE_UPLOAD_PUBLISHER=true        # Set to false to disable file upload
ENABLE_BLOB_CHECK_AGGREGATOR=true        # Set to false to disable file upload

SLEEP_DELAY=2                            # Sleep between failed requests
MAX_RETRIES=100                          # Max retries for checking aggregator & publisher

CACHE_CHECK=true                         # Set to false to disable cache checking on aggregator

FILE_PATH="./random_file.bin"            # Path to generate random file to upload
FILE_SIZE_MB=5                           # Minimum size in MB

STRING_LEN=50                            # Number of characters for the string to upload

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Function to print usage information
usage() {
    echo -e "Usage: $0 [options]"
    echo -e "Options:"
    echo -e "  -a, --aggregator      Aggregator URL (default: $AGGREGATOR)"
    echo -e "  -p, --publisher       Publisher URL (default: $PUBLISHER)"
    echo -e "  -s, --string-upload   Enable/disable string upload (default: $ENABLE_STRING_UPLOAD_PUBLISHER)"
    echo -e "  -f, --file-upload     Enable/disable file upload (default: $ENABLE_FILE_UPLOAD_PUBLISHER)"
    echo -e "  -b, --blob-check      Enable/disable blob check on aggregator (default: $ENABLE_BLOB_CHECK_AGGREGATOR)"
    echo -e "  -d, --delay           Sleep delay between failed requests (default: $SLEEP_DELAY)"
    echo -e "  -r, --max-retries     Max retries for checking aggregator & publisher (default: $MAX_RETRIES)"
    echo -e "  -c, --cache-check     Enable/disable cache checking on aggregator (default: $CACHE_CHECK)"
    echo -e "  -l, --file-size       File size in MB for random file (default: $FILE_SIZE_MB)"
    echo -e "  -n, --string-len      Length of the string to upload (default: $STRING_LEN)"
    echo -e "  -h, --help            Show this help message"
    exit 1
}

# Parse command-line options
while [[ $# -gt 0 ]]; do
    case "$1" in
        -a|--aggregator)
            AGGREGATOR="$2"
            shift 2
            ;;
        -p|--publisher)
            PUBLISHER="$2"
            shift 2
            ;;
        -s|--string-upload)
            ENABLE_STRING_UPLOAD_PUBLISHER="$2"
            shift 2
            ;;
        -f|--file-upload)
            ENABLE_FILE_UPLOAD_PUBLISHER="$2"
            shift 2
            ;;
        -b|--blob-check)
            ENABLE_BLOB_CHECK_AGGREGATOR="$2"
            shift 2
            ;;
        -d|--delay)
            SLEEP_DELAY="$2"
            shift 2
            ;;
        -r|--max-retries)
            MAX_RETRIES="$2"
            shift 2
            ;;
        -c|--cache-check)
            CACHE_CHECK="$2"
            shift 2
            ;;
        -l|--file-size)
            FILE_SIZE_MB="$2"
            shift 2
            ;;
        -n|--string-len)
            STRING_LEN="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo -e "${RED}Error: Invalid option '$1'${NC}"
            usage
            ;;
    esac
done

echo -e "${BLUE}------------------------------SETTINGS-----------------------------${NC}"
echo -e "${BLUE}AGGREGATOR:${NC}     $AGGREGATOR"
echo -e "${BLUE}PUBLISHER:${NC}      $PUBLISHER"
echo -e "${BLUE}SLEEP_DELAY:${NC}    $SLEEP_DELAY seconds"
echo -e "${BLUE}MAX_RETRIES:${NC}    $MAX_RETRIES"
echo -e "${BLUE}CACHE_CHECK:${NC}    $CACHE_CHECK"
echo -e "${BLUE}FILE_PATH:${NC}      $FILE_PATH"
echo -e "${BLUE}FILE_SIZE_MB:${NC}   $FILE_SIZE_MB"
echo -e "${BLUE}STRING_LEN:${NC}     $STRING_LEN characters"

upload_string_blob() {
    RANDOM_STRING=$(tr -dc A-Za-z0-9 </dev/urandom | head -c ${STRING_LEN})
    echo -e "${GREEN}Generated random string: ${NC}${RANDOM_STRING}${NC}"
    echo -e "${GREEN}Uploading string: ${NC}${RANDOM_STRING}${NC}"
    RETRIES=0
    while true; do
        PUBLISH_RESULT=$(curl -s -X PUT "$PUBLISHER/v1/blobs" -d "$RANDOM_STRING")

        if [[ $? -eq 0 && -n "$PUBLISH_RESULT" ]]; then
            break
        fi

        echo -e "${RED}Error: Failed to upload string. Retrying... $RETRIES/$MAX_RETRIES${NC}"
        RETRIES=$((RETRIES + 1))
        if [[ $RETRIES -ge $MAX_RETRIES ]]; then
            echo -e "${RED}String upload failed after multiple retries. Exiting...${NC}"
            exit 1
        fi
        sleep $SLEEP_DELAY
    done

    extract_blob_id "$PUBLISH_RESULT"
}

generate_random_file() {
    echo -e "${GREEN}Generating a random file of ${NC}${FILE_SIZE_MB}MB...${NC}"
    dd if=/dev/urandom of="$FILE_PATH" bs=1M count=$FILE_SIZE_MB status=none
    echo -e "${GREEN}Random file generated: ${NC}${FILE_PATH}${NC}"
}

upload_file_blob() {
    echo -e "${GREEN}Uploading file: ${NC}${FILE_PATH}${NC}"

    RETRIES=0
    while true; do
        PUBLISH_RESULT=$(curl -s -X PUT "$PUBLISHER/v1/blobs?epochs=5" --upload-file "$FILE_PATH")

        if [[ $? -eq 0 && -n "$PUBLISH_RESULT" ]]; then
            break
        fi

        echo -e "${RED}Error: Failed to upload file. Retrying... $RETRIES/$MAX_RETRIES${NC}"
        RETRIES=$((RETRIES + 1))
        if [[ $RETRIES -ge $MAX_RETRIES ]]; then
            echo -e "${RED}File upload failed after multiple retries. Exiting...${NC}"
            exit 1
        fi
        sleep $SLEEP_DELAY
    done

    extract_blob_id "$PUBLISH_RESULT"
}

extract_blob_id() {
    PUBLISH_RESULT="$1"

    if echo "$PUBLISH_RESULT" | grep -q "413 Request Entity Too Large"; then
        echo -e "${RED}Error: Response from Publisher is '413 Request Entity Too Large'. This indicates that the file you are trying to upload exceeds the allowed size limit. Consider settings 'client_max_body_size' to 15M or higher in the Nginx config or set different file size with -l flag in MB${NC}"
        return 1
    fi

    if echo "$PUBLISH_RESULT" | grep -q "Failed to buffer the request body: length limit exceeded"; then
        echo -e "${RED}Error: 'Failed to buffer the request body: length limit exceeded'. This indicates that the file size exceeds the upload limit. Consider increasing the '--max-body-size' value (default 10MiB) to upload larger files.${NC} or set different file size with -l flag in MB${NC}"
        return 1
    fi
    
    if ! echo "$PUBLISH_RESULT" | jq empty 2>/dev/null; then
        echo -e "${RED}Error: Response from Publisher is not valid JSON. Raw response:${NC} $PUBLISH_RESULT"
        return 1
    fi

    BLOB_ID=$(echo "$PUBLISH_RESULT" | jq -r '.newlyCreated.blobObject.blobId // .alreadyCertified.blobId')

    if [[ -z "$BLOB_ID" || "$BLOB_ID" == "null" ]]; then
        echo -e "${RED}Error: Failed to extract blob ID from Publisher. Response:${NC} $PUBLISH_RESULT"
        return 1
    fi

    if echo "$PUBLISH_RESULT" | jq -e '.newlyCreated' >/dev/null; then
        echo -e "${GREEN}Upload successful! Blob ID: ${NC}${BLOB_ID}${NC}"
    elif echo "$PUBLISH_RESULT" | jq -e '.alreadyCertified' >/dev/null; then
        echo -e "${YELLOW}Blob already exists on Publisher. Blob ID: ${NC}${BLOB_ID}${NC}"
    else
        echo -e "${RED}Unexpected response format! Response:${NC} $PUBLISH_RESULT"
        return 1
    fi
    
    if [[ "$ENABLE_BLOB_CHECK_AGGREGATOR" == true ]]; then
        check_aggregator "$BLOB_ID"
    fi
}

check_aggregator() {
    local BLOB_ID="$1"
    echo -e "${GREEN}Checking Blob by ID on Aggregator: ${NC}$BLOB_ID${GREEN}${NC}"

    RETRIES=0
    while true; do
        AGGREGATOR_QUERY_RESULT=$(curl -s "$AGGREGATOR/v1/blobs/$BLOB_ID" | tr -d '\0')

        if [[ $? -ne 0 ]]; then
            # Calculate the retry count and total max retries
            RETRY_COUNT=$((RETRIES + 1))
            echo -e "${RED}Error: Failed to query the aggregator. Retrying... $RETRIES/$MAX_RETRIES${NC}"

            RETRIES=$((RETRIES + 1))
            if [[ $RETRIES -ge $MAX_RETRIES ]]; then
                echo -e "${RED}Blob was not found on aggregator after multiple retries.${NC}"
                return 1
            fi
            sleep $SLEEP_DELAY
            continue
        fi

        if [[ "$AGGREGATOR_QUERY_RESULT" == *"BLOB_NOT_FOUND"* ]]; then
            # Calculate the retry count and total max retries
            RETRY_COUNT=$((RETRIES + 1))
            echo -e "${YELLOW}Blob not found on aggregator yet. Retrying... $RETRIES/$MAX_RETRIES${NC}"
            RETRIES=$((RETRIES + 1))
            if [[ $RETRIES -ge $MAX_RETRIES ]]; then
                echo -e "${RED}Blob was not found on aggregator after multiple retries.${NC}"
                return 1
            fi
            sleep $SLEEP_DELAY
        else
            echo -e "${GREEN}Aggregator returned the Blob by ID: ${NC}$BLOB_ID"

            # Evaluate cache only if CACHE_CHECK is enabled
            if [[ "$CACHE_CHECK" == true ]]; then
                echo -e "${GREEN}Requerying Blob to check Cache: ${NC}${AGGREGATOR}/v1/blobs/${BLOB_ID}"
                CACHE_STATUS=$(curl -s -I "$AGGREGATOR/v1/blobs/$BLOB_ID" | grep -i "X-Cache-Status" | awk '{print $2}' | xargs)
                if [[ "${CACHE_STATUS,,}" =~ "hit" ]]; then
                    echo -e "${GREEN}Cache-Status on Aggregator: HIT | Blob found in cache: ${NC}${BLOB_ID}${NC}"
                elif [[ "${CACHE_STATUS,,}" =~ "miss" ]]; then
                    echo -e "${YELLOW}Cache-Status on Aggregator: MISS | Blob ID: ${NC}${BLOB_ID}${NC}"
                else
                    echo -e "${RED}Error: Cache-Status on Aggregator is unknown or not found."
                fi
            fi
            return 0
        fi
    done
}


while true; do
    if [[ "$ENABLE_STRING_UPLOAD_PUBLISHER" == true ]]; then
        echo -e "${BLUE}-----------------------TESTING STRING UPLOAD-----------------------${NC}"
        upload_string_blob
    else
        echo -e "${YELLOW}String upload is disabled.${NC}"
    fi

    if [[ "$ENABLE_FILE_UPLOAD_PUBLISHER" == true ]]; then
        echo -e "${BLUE}------------------------TESTING FILE UPLOAD------------------------${NC}"
        generate_random_file
        upload_file_blob
    else
        echo -e "${YELLOW}File upload is disabled.${NC}"
    fi

    echo -e "${BLUE}-------------------------------------------------------------------${NC}"
    echo -e "${NC}Press ${RED}CTRL + C${NC} to exit"
    sleep $SLEEP_DELAY
done
