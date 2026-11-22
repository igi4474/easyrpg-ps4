// Checks that the filtered ICU data contains every converter liblcf uses,
// and that real text round-trips correctly.
#include <unicode/ucnv.h>
#include <unicode/ucsdet.h>
#include <unicode/ustring.h>
#include <cstdio>
#include <cstring>
#include <string>

static std::string to_utf8(const char* enc, const std::string& in, UErrorCode& st) {
	char out[512] = {0};
	int32_t n = ucnv_convert("UTF-8", enc, out, sizeof(out), in.data(), (int32_t)in.size(), &st);
	return std::string(out, n > 0 ? n : 0);
}

int main() {
	int fails = 0;
	const char* names[] = {"ibm-943_P15A-2003", "windows-949-2000", "windows-936-2000", "windows-950",
		"windows-1250", "windows-1251", "windows-1252", "windows-1253", "windows-1254", "windows-1255",
		"windows-1256", "windows-1257", "windows-1258", "windows-874", "ibm-5348_P100-1997",
		"ibm-5346_P100-1998", "ibm-5347_P100-1998", "ibm-9448_X100-2005", "ibm-5349_P100-1998",
		"ibm-9447_P100-2002", "Shift_JIS", "UTF-8"};
	for (auto n : names) {
		UErrorCode st = U_ZERO_ERROR;
		UConverter* c = ucnv_open(n, &st);
		if (U_FAILURE(st)) { printf("MISSING converter %-22s %s\n", n, u_errorName(st)); fails++; }
		if (c) ucnv_close(c);
	}
	struct { const char* enc; std::string bytes; const char* expect; } samples[] = {
		{"ibm-943_P15A-2003", "\x83\x65\x83\x58\x83\x67", "テスト"},             // Shift-JIS
		{"windows-1250", "Za\xbf\xf3\xb3\xe6 g\xea\x9cl\xb9 ja\x9f\xf1", "Zażółć gęślą jaźń"}, // Polish
		{"windows-1251", "\xcf\xf0\xe8\xe2\xe5\xf2", "Привет"},                  // Russian
		{"windows-949-2000", "\xc7\xd1\xb1\xb9", "한국"},                        // Korean
		{"windows-936-2000", "\xd6\xd0\xce\xc4", "中文"},                        // Chinese (GBK)
	};
	for (auto& s : samples) {
		UErrorCode st = U_ZERO_ERROR;
		std::string out = to_utf8(s.enc, s.bytes, st);
		bool ok = U_SUCCESS(st) && out == s.expect;
		printf("%s %-18s -> %s\n", ok ? "OK  " : "FAIL", s.enc, out.c_str());
		if (!ok) fails++;
	}
	// Charset detection (liblcf uses it to guess a game's encoding)
	UErrorCode st = U_ZERO_ERROR;
	UCharsetDetector* d = ucsdet_open(&st);
	std::string sj = "\x83\x65\x83\x58\x83\x67\x82\xc5\x82\xb7\x81\x42\x82\xb1\x82\xea\x82\xcd\x93\xfa\x96\x7b\x8c\xea\x82\xcc\x95\xb6\x8f\xcd\x82\xc5\x82\xb7\x81\x42";
	ucsdet_setText(d, sj.data(), (int32_t)sj.size(), &st);
	const UCharsetMatch* m = ucsdet_detect(d, &st);
	const char* name = m ? ucsdet_getName(m, &st) : "none";
	printf("%s detect Shift-JIS text -> %s (%s)\n", (U_SUCCESS(st) && strcmp(name, "Shift_JIS") == 0) ? "OK  " : "FAIL", name, u_errorName(st));
	ucsdet_close(d);
	printf("%s\n", fails ? "SOME TESTS FAILED" : "ALL ENCODING TESTS PASSED");
	return fails != 0;
}
