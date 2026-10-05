import { createClient } from "npm:@supabase/supabase-js@2";

const MAX_FILE_SIZE = 20 * 1024 * 1024;
const MAX_MULTIPART_OVERHEAD = 128 * 1024;
const DEFAULT_BUCKET = "bulas";
const POSTGRES_BIGINT_MAX = 9223372036854775807n;

const CORS_HEADERS: HeadersInit = {
  "Access-Control-Allow-Origin": Deno.env.get("APP_ORIGIN") || "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Max-Age": "86400",
  "Vary": "Origin",
};

class RequestError extends Error {
  readonly status: number;

  constructor(status: number, message: string) {
    super(message);
    this.status = status;
  }
}

function jsonResponse(status: number, payload: Record<string, unknown>): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: {
      ...CORS_HEADERS,
      "Cache-Control": "no-store",
      "Content-Type": "application/json; charset=utf-8",
    },
  });
}

function firstKeyFromJsonEnv(name: string): string | null {
  const value = Deno.env.get(name)?.trim();
  if (!value) return null;

  try {
    const parsed: unknown = JSON.parse(value);
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return null;

    const keyMap = parsed as Record<string, unknown>;
    if (typeof keyMap.default === "string" && keyMap.default.trim()) {
      return keyMap.default.trim();
    }

    const firstStringKey = Object.values(keyMap).find(
      (candidate): candidate is string => typeof candidate === "string" && candidate.trim().length > 0,
    );
    return firstStringKey?.trim() ?? null;
  } catch {
    return null;
  }
}

function requiredEnv(name: string, alternativeJsonEnv?: string): string {
  const directValue = Deno.env.get(name)?.trim();
  const value = directValue || (alternativeJsonEnv ? firstKeyFromJsonEnv(alternativeJsonEnv) : null);
  if (!value) {
    throw new RequestError(500, "Configuração obrigatória da função ausente.");
  }
  return value;
}

function getBearerToken(request: Request): string | null {
  const authorization = request.headers.get("authorization")?.trim() ?? "";
  const match = authorization.match(/^Bearer\s+(.+)$/i);
  return match?.[1]?.trim() || null;
}

function normalizeProductName(value: string): string {
  return value
    .normalize("NFKD")
    .replace(/[\u0300-\u036f]/g, "")
    .trim()
    .replace(/\s+/g, " ")
    .toLocaleLowerCase("pt-BR");
}

function sanitizeFileBaseName(originalName: string): string {
  // Remove caminhos fornecidos pelo cliente antes de normalizar o nome.
  const basename = originalName.split(/[\\/]/).pop() || "bula";
  const withoutExtension = basename.replace(/\.[^.]*$/, "");
  const safeName = withoutExtension
    .normalize("NFKD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9_-]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 80);

  return safeName || "bula";
}

async function hasPdfSignature(file: File): Promise<boolean> {
  // A assinatura é conferida no conteúdo, sem confiar na extensão ou no MIME do navegador.
  const initialBytes = new Uint8Array(await file.slice(0, 1024).arrayBuffer());
  const signature = [0x25, 0x50, 0x44, 0x46, 0x2d]; // %PDF-

  for (let offset = 0; offset <= initialBytes.length - signature.length; offset += 1) {
    if (signature.every((byte, index) => initialBytes[offset + index] === byte)) {
      return true;
    }
  }

  return false;
}

Deno.serve(async (request: Request): Promise<Response> => {
  if (request.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }

  if (request.method !== "POST") {
    return jsonResponse(405, { success: false, error: "Método não permitido." });
  }

  try {
    const accessToken = getBearerToken(request);
    if (!accessToken) {
      return jsonResponse(401, { success: false, error: "Autenticação necessária." });
    }

    const supabaseUrl = requiredEnv("SUPABASE_URL");
    const publishableKey = requiredEnv("SUPABASE_ANON_KEY", "SUPABASE_PUBLISHABLE_KEYS");
    const serviceRoleKey = requiredEnv("SUPABASE_SERVICE_ROLE_KEY", "SUPABASE_SECRET_KEYS");
    const adminEmail = Deno.env.get("ADMIN_EMAIL")?.trim().toLocaleLowerCase("pt-BR");
    const bucket = Deno.env.get("BULA_BUCKET")?.trim() || DEFAULT_BUCKET;

    if (!adminEmail) {
      return jsonResponse(500, { success: false, error: "E-mail administrador não configurado." });
    }

    // auth.jwt() é um helper de SQL. Na Edge Function, o JWT é verificado pelo Supabase Auth.
    const authClient = createClient(supabaseUrl, publishableKey, {
      auth: {
        autoRefreshToken: false,
        detectSessionInUrl: false,
        persistSession: false,
      },
    });
    const { data: authData, error: authError } = await authClient.auth.getUser(accessToken);
    const user = authData?.user ?? null;

    if (authError || !user) {
      return jsonResponse(401, { success: false, error: "Sessão inválida ou expirada." });
    }

    if (user.email?.trim().toLocaleLowerCase("pt-BR") !== adminEmail) {
      return jsonResponse(403, { success: false, error: "Apenas o administrador pode enviar bulas." });
    }

    const requestContentType = request.headers.get("content-type")?.toLowerCase() ?? "";
    if (!requestContentType.startsWith("multipart/form-data")) {
      return jsonResponse(415, { success: false, error: "Envie o arquivo como multipart/form-data." });
    }

    const contentLengthHeader = request.headers.get("content-length");
    if (contentLengthHeader && /^\d+$/.test(contentLengthHeader)) {
      const contentLength = Number(contentLengthHeader);
      if (Number.isFinite(contentLength) && contentLength > MAX_FILE_SIZE + MAX_MULTIPART_OVERHEAD) {
        return jsonResponse(413, { success: false, error: "O arquivo excede o limite de 20 MB." });
      }
    }

    let formData: FormData;
    try {
      formData = await request.formData();
    } catch {
      return jsonResponse(400, { success: false, error: "Formulário de upload inválido." });
    }

    const fileFields = formData.getAll("file");
    const file = fileFields.length === 1 && fileFields[0] instanceof File
      ? fileFields[0]
      : null;
    const productField = formData.get("produto");
    const itemIdField = formData.get("item_id");

    if (!file) {
      return jsonResponse(400, { success: false, error: "Envie exatamente um arquivo no campo file." });
    }

    if (typeof productField !== "string" || !productField.trim() || productField.length > 200) {
      return jsonResponse(400, { success: false, error: "Produto inválido." });
    }

    if (typeof itemIdField !== "string") {
      return jsonResponse(400, { success: false, error: "item_id inválido." });
    }

    const itemId = itemIdField.trim();
    if (!/^[1-9]\d{0,18}$/.test(itemId) || BigInt(itemId) > POSTGRES_BIGINT_MAX) {
      return jsonResponse(400, { success: false, error: "item_id deve ser um identificador numérico válido." });
    }

    if (file.size === 0) {
      return jsonResponse(400, { success: false, error: "O arquivo está vazio." });
    }

    if (file.size > MAX_FILE_SIZE) {
      return jsonResponse(413, { success: false, error: "O arquivo excede o limite de 20 MB." });
    }

    if (!(await hasPdfSignature(file))) {
      return jsonResponse(415, { success: false, error: "O conteúdo enviado não tem assinatura de PDF válida." });
    }

    // O app cria ou carrega a linha de estoque antes de chamar esta função.
    const adminClient = createClient(supabaseUrl, serviceRoleKey, {
      auth: {
        autoRefreshToken: false,
        detectSessionInUrl: false,
        persistSession: false,
      },
    });
    const { data: stockItem, error: stockLookupError } = await adminClient
      .from("estoque")
      .select("id, produto")
      .eq("id", itemId)
      .maybeSingle();

    if (stockLookupError) {
      console.error("[upload-bula] Falha ao validar item_id:", stockLookupError.message);
      return jsonResponse(500, { success: false, error: "Não foi possível validar o item do estoque." });
    }

    if (!stockItem) {
      return jsonResponse(404, { success: false, error: "O item informado não existe no estoque." });
    }

    if (normalizeProductName(String(stockItem.produto ?? "")) !== normalizeProductName(productField)) {
      return jsonResponse(409, { success: false, error: "O produto não corresponde ao item informado." });
    }

    const safeFileName = sanitizeFileBaseName(file.name);
    const storagePath = itemId + "/" + crypto.randomUUID() + "-" + safeFileName + ".pdf";
    const { error: uploadError } = await adminClient.storage
      .from(bucket)
      .upload(storagePath, file, {
        cacheControl: "3600",
        contentType: "application/pdf",
        upsert: false,
      });

    if (uploadError) {
      console.error("[upload-bula] Falha no Storage:", uploadError.message);
      return jsonResponse(502, { success: false, error: "Não foi possível salvar a bula no Storage." });
    }

    // O app grava esta URL no estoque e no cadastro permanente do produto.
    const { data: publicUrlData } = adminClient.storage
      .from(bucket)
      .getPublicUrl(storagePath);

    return jsonResponse(201, {
      success: true,
      url: publicUrlData.publicUrl,
      path: storagePath,
    });
  } catch (error) {
    if (error instanceof RequestError) {
      return jsonResponse(error.status, { success: false, error: error.message });
    }

    console.error("[upload-bula] Erro inesperado:", error);
    return jsonResponse(500, { success: false, error: "Falha interna ao enviar a bula." });
  }
});
