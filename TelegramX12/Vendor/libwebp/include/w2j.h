/*
 * webp2jpeg - rdzeń konwersji WebP -> JPEG.
 *
 * Kod jest przenośny (czysty C99) i działa m.in. na iOS 12, gdzie system
 * nie potrafi dekodować WebP (wsparcie pojawiło się dopiero w iOS 14).
 *
 *   dekodowanie + skalowanie : libwebp  (third_party/libwebp)
 *   kodowanie JPEG           : stb_image_write (domena publiczna)
 */
#ifndef WEBP2JPEG_W2J_H
#define WEBP2JPEG_W2J_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define W2J_VERSION "1.0.0"

/* Domyślna jakość JPEG (zakres 1..100). */
#define W2J_DEFAULT_QUALITY 90
#define W2J_DEFAULT_QUALITY_STR "90"

typedef struct w2j_options {
    int quality;           /* 1..100; 0 oznacza „użyj domyślnej" */
    int max_width;         /* maks. szerokość w px; 0 = bez skalowania */
    unsigned background;   /* 0xRRGGBB - tło pod przezroczystymi pikselami */
} w2j_options;

/* Informacje o strumieniu WebP (bez dekodowania pikseli). */
typedef struct w2j_info {
    int width;
    int height;
    int has_alpha;       /* 0/1 */
    int has_animation;   /* 0/1 - konwerter przetwarza pierwszą klatkę */
    int format;          /* 0=nieznany, 1=strata, 2=bezstratny, 3=mieszany */
} w2j_info;

/* Wynik konwersji. */
typedef struct w2j_result {
    uint8_t *jpeg;       /* bufor z wynikiem - zwolnić przez w2j_result_free */
    size_t jpeg_size;    /* rozmiar w bajtach */
    int width;           /* wymiary obrazu wyjściowego (po skalowaniu) */
    int height;
} w2j_result;

void w2j_options_default(w2j_options *opt);

/*
 * Wypełnia `info` danymi nagłówka WebP.
 * Zwraca 0 przy sukcesie, niezerową wartość przy błędzie (opis w `err`).
 */
int w2j_probe(const uint8_t *webp, size_t webp_size,
              w2j_info *info, char *err, size_t err_size);

/*
 * Konwertuje WebP na JPEG.
 *
 *   webp      - surowe bajty pliku .webp
 *   webp_size - rozmiar wejścia w bajtach
 *   opt       - opcje; NULL = ustawienia domyślne
 *   result    - na wyjściu wynik (wymagane)
 *   err       - opcjonalny bufor na komunikat błędu
 *
 * Zwraca 0 przy sukcesie, niezerowo przy błędzie.
 */
int w2j_convert(const uint8_t *webp, size_t webp_size,
                const w2j_options *opt,
                w2j_result *result,
                char *err, size_t err_size);

/* Zwalnia zasoby wyniku (bezpieczne też dla wyniku zerowanego). */
void w2j_result_free(w2j_result *result);

#ifdef __cplusplus
}
#endif

#endif /* WEBP2JPEG_W2J_H */
