// Stub HttpClient - will be replaced with real implementation
export const http = {
  async get(_url: string) {
    return { data: null }
  },
  async post(_url: string, _body: unknown) {
    return { data: null }
  }
}
