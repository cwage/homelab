FROM openbao/openbao:2.4.4

# Add commonly-needed CLI tools for ad-hoc secret/cert work. The upstream
# openbao image is alpine + bao only — no jq for JSON output, no openssl
# for cert inspection, no curl for raw API pokes — so the basics live here.
# Image's default USER is root, so no user switch needed.
RUN apk add --no-cache jq openssl curl
