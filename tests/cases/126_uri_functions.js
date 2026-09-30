// §19.2.6 encodeURI/encodeURIComponent/decodeURI/decodeURIComponent, escape/unescape (Annex B).
const s = "a b&c=d/é?😀#";
console.log("enc", encodeURIComponent(s), encodeURI(s));
console.log("dec", decodeURIComponent(encodeURIComponent(s)) === s, decodeURI("%2F%20"), decodeURIComponent("%2F%20"));
try { encodeURIComponent("\uD800"); } catch (e) { console.log(e.name); }
try { decodeURIComponent("%E0%A4%A"); } catch (e) { console.log(e.name); }
console.log("reserved", encodeURIComponent("-_.!~*'()"), encodeURI(";,/?:@&=+$#"));
console.log("annex b", escape("a b+é"), unescape("%u00E9%20"));
