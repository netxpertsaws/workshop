package com.mayooran.workshop;

import com.google.gson.Gson;

import javax.servlet.ServletException;
import javax.servlet.annotation.WebServlet;
import javax.servlet.http.HttpServlet;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Timestamp;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * GET /api/registrations
 *
 * Returns every row in the registrations table as JSON, newest first.
 * Optional query parameter: ?workshop=<name>  filters by workshop.
 *
 * Response shape:
 *   200 {
 *     "status": "ok",
 *     "count": 3,
 *     "registrations": [
 *       { "id": 17, "studentName": "...", "studentNo": "...",
 *         "workshop": "...", "registeredAt": "2026-06-04T08:15:32Z" },
 *       ...
 *     ]
 *   }
 *   500 { "status": "error", "message": "..." }
 */
@WebServlet(name = "RegistrationListServlet", urlPatterns = {"/api/registrations"})
public class RegistrationListServlet extends HttpServlet {

    private static final Gson GSON = new Gson();

    @Override
    protected void doGet(HttpServletRequest req, HttpServletResponse resp)
            throws ServletException, IOException {

        resp.setContentType("application/json;charset=UTF-8");
        resp.setHeader("Cache-Control", "no-store");

        String workshopFilter = req.getParameter("workshop");
        boolean hasFilter = workshopFilter != null && !workshopFilter.trim().isEmpty();

        String sql = "SELECT id, student_name, student_no, workshop, registered_at "
                   + "FROM registrations "
                   + (hasFilter ? "WHERE workshop = ? " : "")
                   + "ORDER BY registered_at DESC";

        List<Registration> rows = new ArrayList<>();

        try (Connection conn = DatabaseConfig.getDataSource().getConnection();
             PreparedStatement stmt = conn.prepareStatement(sql)) {

            if (hasFilter) {
                stmt.setString(1, workshopFilter.trim());
            }

            try (ResultSet rs = stmt.executeQuery()) {
                while (rs.next()) {
                    Registration r = new Registration();
                    r.id           = rs.getLong("id");
                    r.studentName  = rs.getString("student_name");
                    r.studentNo    = rs.getString("student_no");
                    r.workshop     = rs.getString("workshop");
                    Timestamp ts   = rs.getTimestamp("registered_at");
                    r.registeredAt = ts == null ? null : ts.toInstant().toString();
                    rows.add(r);
                }
            }

            Map<String, Object> body = new HashMap<>();
            body.put("status", "ok");
            body.put("count", rows.size());
            body.put("registrations", rows);
            resp.getWriter().write(GSON.toJson(body));

        } catch (SQLException ex) {
            log("DB error fetching registrations", ex);
            resp.setStatus(HttpServletResponse.SC_INTERNAL_SERVER_ERROR);
            Map<String, String> err = new HashMap<>();
            err.put("status", "error");
            err.put("message", "Failed to fetch registrations.");
            resp.getWriter().write(GSON.toJson(err));
        }
    }

    /** DTO matching the JSON output. */
    private static final class Registration {
        long id;
        String studentName;
        String studentNo;
        String workshop;
        String registeredAt;
    }
}
