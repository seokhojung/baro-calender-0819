# 멀티 스테이지 빌드를 위한 베이스 이미지
FROM node:18-alpine AS base

# 작업 디렉토리 설정
WORKDIR /app

# 패키지 파일 복사
COPY package*.json ./
COPY client/package*.json ./client/

# 프로덕션 의존성만 설치
FROM base AS deps
RUN npm ci --only=production && npm cache clean --force
RUN cd client && npm ci --only=production && npm cache clean --force

# 개발 의존성 설치
FROM base AS deps-dev
RUN npm ci && npm cache clean --force
RUN cd client && npm ci && npm cache clean --force

# 빌드 스테이지
FROM base AS builder
COPY --from=deps-dev /app/node_modules ./node_modules
COPY --from=deps-dev /app/client/node_modules ./client/node_modules
COPY . .

# 클라이언트 빌드
RUN cd client && npm run build

# 프로덕션 이미지
FROM base AS production
ENV NODE_ENV=production

# 보안을 위한 non-root 사용자 생성
RUN addgroup -g 1001 -S nodejs
RUN adduser -S nodejs -u 1001

# 의존성 복사
COPY --from=deps /app/node_modules ./node_modules
COPY --from=deps /app/client/node_modules ./client/node_modules

# 애플리케이션 코드 복사
COPY --from=builder /app/src ./src
COPY --from=builder /app/client/.next ./client/.next
COPY --from=builder /app/client/public ./client/public
COPY --from=builder /app/package*.json ./
COPY --from=builder /app/client/package*.json ./client/

# 권한 설정
RUN chown -R nodejs:nodejs /app
USER nodejs

# 헬스체크
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD node -e "require('http').get('http://localhost:3000/health', (res) => { process.exit(res.statusCode === 200 ? 0 : 1) })" || exit 1

# 포트 노출
EXPOSE 3000

# 애플리케이션 실행
CMD ["npm", "start"]

# 개발 이미지
FROM base AS development
ENV NODE_ENV=development

# 개발 의존성 복사
COPY --from=deps-dev /app/node_modules ./node_modules
COPY --from=deps-dev /app/client/node_modules ./client/node_modules

# 소스 코드 복사
COPY . .

# 포트 노출
EXPOSE 3000

# 개발 서버 실행
CMD ["npm", "run", "dev"]
