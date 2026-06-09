package com.mayooran.workshop;

import com.zaxxer.hikari.HikariConfig;
import com.zaxxer.hikari.HikariDataSource;

import javax.servlet.ServletContextEvent;
import javax.servlet.ServletContextListener;
import javax.servlet.annotation.WebListener;
import javax.sql.DataSource;

/**
 * Singleton DataSource backed by HikariCP.
 *
 * All connection parameters are read from environment variables — never
 * hard-coded — so the same WAR runs on any environment:
 *
 *   DB_HOST       (default: localhost)
 *   DB_PORT       (default: 3306)
 *   DB_NAME       (required)
 *   DB_USER       (required)
 *   DB_PASSWORD   (required)
 *   DB_POOL_SIZE  (default: 5)
 */
@WebListener
public class DatabaseConfig implements ServletContextListener {

    private static volatile HikariDataSource dataSource;

    public static DataSource getDataSource() {
        if (dataSource == null) {
            synchronized (DatabaseConfig.class) {
                if (dataSource == null) {
                    dataSource = build();
                }
            }
        }
        return dataSource;
    }

    private static HikariDataSource build() {
        String host     = env("DB_HOST",     "localhost");
        String port     = env("DB_PORT",     "3306");
        String name     = required("DB_NAME");
        String user     = required("DB_USER");
        String password = required("DB_PASSWORD");
        int poolSize    = Integer.parseInt(env("DB_POOL_SIZE", "5"));

        String jdbcUrl = String.format(
            "jdbc:mysql://%s:%s/%s?useSSL=false&serverTimezone=UTC"
                + "&allowPublicKeyRetrieval=true&useUnicode=true"
                + "&characterEncoding=utf8",
            host, port, name);

        HikariConfig cfg = new HikariConfig();
        cfg.setJdbcUrl(jdbcUrl);
        cfg.setUsername(user);
        cfg.setPassword(password);
        cfg.setDriverClassName("com.mysql.cj.jdbc.Driver");
        cfg.setMaximumPoolSize(poolSize);
        cfg.setConnectionTimeout(10_000);
        cfg.setPoolName("WorkshopPool");
        cfg.addDataSourceProperty("cachePrepStmts", "true");
        cfg.addDataSourceProperty("prepStmtCacheSize", "250");

        return new HikariDataSource(cfg);
    }

    private static String env(String key, String defaultValue) {
        String v = System.getenv(key);
        return (v == null || v.isEmpty()) ? defaultValue : v;
    }

    private static String required(String key) {
        String v = System.getenv(key);
        if (v == null || v.isEmpty()) {
            throw new IllegalStateException(
                "Required environment variable not set: " + key);
        }
        return v;
    }

    @Override
    public void contextInitialized(ServletContextEvent sce) {
        getDataSource(); // warm up the pool at startup
        sce.getServletContext().log("DatabaseConfig initialised.");
    }

    @Override
    public void contextDestroyed(ServletContextEvent sce) {
        if (dataSource != null && !dataSource.isClosed()) {
            dataSource.close();
        }
    }
}
