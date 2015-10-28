{
  "diffy" = {
    version = "3.0.2";
    source = {
      type = "gem";
      sha256 = "15qyjmmspc52dlp91yc6ij5bkn61pp8j6i7pk9gyba8q430sd2v4";
    };
  };
  "domain_name" = {
    version = "0.5.25";
    source = {
      type = "gem";
      sha256 = "16qvfrmcwlzz073aas55mpw2nhyhjcn96s524w0g1wlml242hjav";
    };
    dependencies = [
      "unf"
    ];
  };
  "haml" = {
    version = "4.0.5";
    source = {
      type = "gem";
      sha256 = "1xmzb0k5q271090crzmv7dbw8ss4289bzxklrc0fhw6pw3kcvc85";
    };
    dependencies = [
      "tilt"
    ];
  };
  "http-cookie" = {
    version = "1.0.2";
    source = {
      type = "gem";
      sha256 = "0cz2fdkngs3jc5w32a6xcl511hy03a7zdiy988jk1sf3bf5v3hdw";
    };
    dependencies = [
      "domain_name"
    ];
  };
  "mechanize" = {
    version = "2.7.3";
    source = {
      type = "gem";
      sha256 = "00jkazj8fqnynaxca0lnwx5a084irxrnw8n8i0kppq4vg71g7rrx";
    };
    dependencies = [
      "domain_name"
      "http-cookie"
      "mime-types"
      "net-http-digest_auth"
      "net-http-persistent"
      "nokogiri"
      "ntlm-http"
      "webrobots"
    ];
  };
  "mime-types" = {
    version = "2.6.2";
    source = {
      type = "gem";
      sha256 = "136ybsrwn1k7zcbxbrczf0n4z3liy5ygih3q9798s8pi80smi5dm";
    };
  };
  "mini_portile" = {
    version = "0.6.2";
    source = {
      type = "gem";
      sha256 = "0h3xinmacscrnkczq44s6pnhrp4nqma7k056x5wv5xixvf2wsq2w";
    };
  };
  "net-http-digest_auth" = {
    version = "1.4";
    source = {
      type = "gem";
      sha256 = "14801gr34g0rmqz9pv4rkfa3crfdbyfk6r48vpg5a5407v0sixqi";
    };
  };
  "net-http-persistent" = {
    version = "2.9.4";
    source = {
      type = "gem";
      sha256 = "1y9fhaax0d9kkslyiqi1zys6cvpaqx9a0y0cywp24rpygwh4s9r4";
    };
  };
  "nokogiri" = {
    version = "1.6.6.2";
    source = {
      type = "gem";
      sha256 = "1j4qv32qjh67dcrc1yy1h8sqjnny8siyy4s44awla8d6jk361h30";
    };
    dependencies = [
      "mini_portile"
    ];
  };
  "ntlm-http" = {
    version = "0.1.1";
    source = {
      type = "gem";
      sha256 = "0yx01ffrw87wya1syivqzf8hz02axk7jdpw6aw221xwvib767d36";
    };
  };
  "pg" = {
    version = "0.17.1";
    source = {
      type = "gem";
      sha256 = "19hhlq5cp0cgm9b8daxjn8rkk8fq7bxxv1gd43l2hk0qgy7kx4z7";
    };
  };
  "rack" = {
    version = "1.5.2";
    source = {
      type = "gem";
      sha256 = "19szfw76cscrzjldvw30jp3461zl00w4xvw1x9lsmyp86h1g0jp6";
    };
  };
  "rack-protection" = {
    version = "1.5.2";
    source = {
      type = "gem";
      sha256 = "0qabb9d3i0fy9prwwmjxzb3xx4n1myb88dcsri4m27sc8ylcv6kz";
    };
    dependencies = [
      "rack"
    ];
  };
  "sequel" = {
    version = "4.8.0";
    source = {
      type = "gem";
      sha256 = "0cybz6b5f05jr57xps62zwxw0ba4pwh8g7pyaykm4pnv5wbrjchp";
    };
  };
  "sinatra" = {
    version = "1.4.4";
    source = {
      type = "gem";
      sha256 = "12iy0f92d3zyk4759flgcracrbzc3x6cilpgdkzhzgjrsm9aa5hs";
    };
    dependencies = [
      "rack"
      "rack-protection"
      "tilt"
    ];
  };
  "sqlite3" = {
    version = "1.3.9";
    source = {
      type = "gem";
      sha256 = "07m6a6flmyyi0rkg0j7x1a9861zngwjnximfh95cli2zzd57914r";
    };
  };
  "tilt" = {
    version = "1.3.4";
    source = {
      type = "gem";
      sha256 = "0hw59shnf3vgpx1jv24mj0d48m72h5cm1d4bianhhkjj82mc406a";
    };
  };
  "unf" = {
    version = "0.1.4";
    source = {
      type = "gem";
      sha256 = "0bh2cf73i2ffh4fcpdn9ir4mhq8zi50ik0zqa1braahzadx536a9";
    };
    dependencies = [
      "unf_ext"
    ];
  };
  "unf_ext" = {
    version = "0.0.7.1";
    source = {
      type = "gem";
      sha256 = "0ly2ms6c3irmbr1575ldyh52bz2v0lzzr2gagf0p526k12ld2n5b";
    };
  };
  "webrobots" = {
    version = "0.1.1";
    source = {
      type = "gem";
      sha256 = "1jlnhhpa1mkrgsmihs2qx13z3n6xhswjnlk5a2ypyplw2id5x32n";
    };
  };
}