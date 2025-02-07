const { addonBuilder } = require("stremio-addon-sdk");
const axios = require("axios");
const fs = require("fs");

// URL chứa danh sách tài khoản
const DATA_URL = "https://duchoa.biz/data.txt";

// API của Fshare
const API_LOGIN = "https://api2.fshare.vn/api/user/login";
const API_GET_LINK = "https://api2.fshare.vn/api/session/download";

const manifest = {
    id: "fshare-stremio",
    version: "1.0.0",
    name: "Fshare Stremio",
    description: "Addon xem phim từ Fshare.vn bằng tài khoản VIP",
    types: ["movie", "series"],
    catalogs: [],
    resources: ["stream"]
};

const builder = new addonBuilder(manifest);

// Hàm lấy danh sách tài khoản từ file data.txt
async function getAccount() {
    try {
        const res = await axios.get(DATA_URL);
        const lines = res.data.split("\n").map(line => line.trim()).filter(line => line);
        if (lines.length === 0) return null;
        const randomLine = lines[Math.floor(Math.random() * lines.length)];
        const [email, password] = randomLine.split(":");
        return { email, password };
    } catch (error) {
        console.error("Lỗi lấy danh sách tài khoản:", error);
        return null;
    }
}

// Hàm đăng nhập vào Fshare để lấy token
async function loginFshare(email, password) {
    try {
        const response = await axios.post(API_LOGIN, {
            user_email: email,
            password: password,
            app_key: "L2S7R6ZMagggC5wWkQhX2+aDi467PPuftWUMRFSn"
        });

        if (response.data.msg === "Login successfully!") {
            return {
                token: response.data.token,
                session_id: response.data.session_id
            };
        } else {
            throw new Error("Đăng nhập thất bại!");
        }
    } catch (error) {
        console.error("Lỗi đăng nhập Fshare:", error);
        return null;
    }
}

// Hàm lấy direct link từ Fshare
async function getDirectLink(url, token, session_id) {
    try {
        const response = await axios.post(API_GET_LINK, { token, url }, {
            headers: {
                "Authorization": `Bearer ${token}`,
                "Content-Type": "application/json",
                "User-Agent": "Dalvik/2.1.0"
            },
            cookies: { session_id }
        });

        if (response.data.location) {
            return response.data.location;
        } else {
            throw new Error("Không lấy được link tải!");
        }
    } catch (error) {
        console.error("Lỗi lấy direct link Fshare:", error);
        return null;
    }
}

// Xử lý yêu cầu stream từ Stremio
builder.defineStreamHandler(async ({ type, id }) => {
    if (type !== "movie" && type !== "series") return { streams: [] };

    // Giả sử ID là link Fshare (hoặc cần mapping từ ID sang link)
    const fshareUrl = `https://www.fshare.vn/file/${id}`;

    const account = await getAccount();
    if (!account) return { streams: [] };

    const auth = await loginFshare(account.email, account.password);
    if (!auth) return { streams: [] };

    const directLink = await getDirectLink(fshareUrl, auth.token, auth.session_id);
    if (!directLink) return { streams: [] };

    return {
        streams: [{
            title: "Xem phim Fshare",
            url: directLink
        }]
    };
});

module.exports = builder.getInterface();
