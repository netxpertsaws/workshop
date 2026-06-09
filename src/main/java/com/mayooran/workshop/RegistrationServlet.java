package com.mayooran.workshop;

import com.google.gson.Gson;

import javax.servlet.ServletException;
import javax.servlet.annotation.WebServlet;
import javax.servlet.http.HttpServlet;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;
import java.io.BufferedReader;
import java.io.IOException;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import java.sql.Timestamp;
import java.time.Instant;
import java.util.HashMap;
import java.util.Map;
import java.util.stream.Collectors;

/**
 * POST /api/register
 *
 * Accepts JSON: { "studentName": "...", "studentNo": "...", "workshop": "..." }
 * Inserts into registrations table and returns JSON:
 *   201 { "status": "ok", "id": <generated_id> }
 *   400 { "status": "error", "message": "..." }
 *   500 { "status": "error", "message": "..." }
 */
@WebServlet(name = "RegistrationServlet", urlPatterns = {"/api/register"})
public class RegistrationServlet extends HttpServlet {

    private static final Gson GSON = new Gson();
    private static final int MAX_NAME_LEN     = 120;
    private static final int MAX_STUDENT_NO   = 40;
    private static final int MAX_WORKSHOP_LEN = 100;

    @Override
    protected void doPost(HttpServletRequest req, HttpServletResponse resp)
            throws ServletException, IOException {

        resp.setContentType("application/json;charset=UTF-8");
        resp.setHeader("Cache-Control", "no-store");

        // 1. Read JSON payload
        String body;
        try (BufferedReader reader = req.getReader()) {
            body = reader.lines().collect(Collectors.joining(System.lineSeparator()));
        }

        RegistrationPayload payload;
        try {
            payload = GSON.fromJson(body, RegistrationPayload.class);
        } catch (Exception e) {
            sendError(resp, HttpServletResponse.SC_BAD_REQUEST, "Invalid JSON payload.");
            return;
        }

        // 2. Validate
        if (payload == null) {
            sendError(resp, HttpServletResponse.SC_BAD_REQUEST, "Empty request body.");
            return;
        }
        String name      = trim(payload.studentName);
        String studentNo = trim(payload.studentNo);
        String workshop  = trim(payload.workshop);

        if (name.isEmpty() || studentNo.isEmpty()) {
            sendError(resp, HttpServletResponse.SC_BAD_REQUEST,
                "studentName and studentNo are required.");
            return;
        }
        if (name.length() > MAX_NAME_LEN
                || studentNo.length() > MAX_STUDENT_NO
                || workshop.length() > MAX_WORKSHOP_LEN) {
            sendError(resp, HttpServletResponse.SC_BAD_REQUEST,
                "One or more fields exceed allowed length.");
            return;
        }

        // 3. Insert with PreparedStatement (parameterised — SQL-injection safe)
        String sql = "INSERT INTO registrations "
                   + "(student_name, student_no, workshop, registered_at) "
                   + "VALUES (?, ?, ?, ?)";

        try (Connection conn = DatabaseConfig.getDataSource().getConnection();
             PreparedStatement stmt = conn.prepareStatement(sql,
                     Statement.RETURN_GENERATED_KEYS)) {

            stmt.setString(1, name);
            stmt.setString(2, studentNo);
            stmt.setString(3, workshop.isEmpty() ? null : workshop);
            stmt.setTimestamp(4, Timestamp.from(Instant.now()));

            int affected = stmt.executeUpdate();
            if (affected == 0) {
                sendError(resp, HttpServletResponse.SC_INTERNAL_SERVER_ERROR,
                    "Insert failed.");
                return;
            }

            long generatedId = -1;
            try (ResultSet keys = stmt.getGeneratedKeys()) {
                if (keys.next()) generatedId = keys.getLong(1);
            }

            Map<String, Object> ok = new HashMap<>();
            ok.put("status", "ok");
            ok.put("id", generatedId);
            ok.put("message", "Registration received.");
            resp.setStatus(HttpServletResponse.SC_CREATED);
            resp.getWriter().write(GSON.toJson(ok));

        } catch (SQLException ex) {
            log("DB error during registration", ex);
            // Handle duplicate-student-number per workshop gracefully
            if (ex.getErrorCode() == 1062) {
                sendError(resp, HttpServletResponse.SC_CONFLICT,
                    "This student number is already registered for the workshop.");
            } else {
                sendError(resp, HttpServletResponse.SC_INTERNAL_SERVER_ERROR,
                    "Server error. Please try again later.");
            }
        }
    }

    private static String trim(String s) {
        return s == null ? "" : s.trim();
    }

    private static void sendError(HttpServletResponse resp, int status, String msg)
            throws IOException {
        resp.setStatus(status);
        Map<String, String> err = new HashMap<>();
        err.put("status", "error");
        err.put("message", msg);
        resp.getWriter().write(GSON.toJson(err));
    }

    /** DTO matching the inbound JSON. */
    private static final class RegistrationPayload {
        String studentName;
        String studentNo;
        String workshop;
    }
}
