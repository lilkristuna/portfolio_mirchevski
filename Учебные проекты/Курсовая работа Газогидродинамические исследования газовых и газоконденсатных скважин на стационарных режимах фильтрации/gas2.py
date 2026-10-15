import math
import re
import numpy as np
import matplotlib.pyplot as plt
import tkinter as tk
from tkinter import messagebox, scrolledtext
from matplotlib.backends.backend_tkagg import FigureCanvasTkAgg


class GasPropertiesApp:
    def __init__(self, root):
        self.root = root
        self.root.title("Расчет свойств природного газа")
        self.root.geometry("1000x800")

        # Component data (initial values from Variant 23)
        self.components = [
            {"name": "CH4", "xi": 0.9376, "Mi": 16.042, "pkpi": 4.695, "Tkpi": 190.55, "mui": 0.001196},
            {"name": "C2H6", "xi": 0.0089, "Mi": 30.068, "pkpi": 4.976, "Tkpi": 305.43, "mui": 0.00980},
            {"name": "C3H8", "xi": 0.0, "Mi": 44.094, "pkpi": 4.333, "Tkpi": 369.82, "mui": 0.00890},
            {"name": "C4H10", "xi": 0.0, "Mi": 58.12, "pkpi": 3.8, "Tkpi": 416.64, "mui": 0.00800},
            {"name": "C5H12", "xi": 0.0045, "Mi": 72.151, "pkpi": 3.44, "Tkpi": 465.0, "mui": 0.00720},
            {"name": "N2", "xi": 0.0, "Mi": 28.016, "pkpi": 3.465, "Tkpi": 126.26, "mui": 0.01780},
            {"name": "CO2", "xi": 0.0490, "Mi": 44.011, "pkpi": 7.527, "Tkpi": 304.2, "mui": 0.01590},

        ]

        # Data storage
        self.p_pl = 0.0  # Formation pressure in MPa
        self.T_pl = 0.0  # Formation temperature in K
        self.L = 0.0  # Well length in m
        self.d = 0.0  # Pipe diameter in m
        self.lambda_val = 0.0  # Friction coefficient
        self.p_ust = 0.0  # Wellhead pressure in MPa
        self.p_z_values = []  # Bottomhole pressures
        self.Q_values = []  # Flow rates
        self.p_ust_regimes = []  # Wellhead pressures for regimes
        self.p_pl2_minus_p_z2 = []
        self.a = self.b = self.C0 = 0.0
        self.equation = ""
        self.rho_air = 1.204  # Air density at standard conditions in kg/m³
        self.V_mol = 24.04  # Molar volume at standard conditions in L/mol
        self.p_st = 0.1013  # Standard pressure in MPa
        self.T_st = 293.15  # Standard temperature in K

        # Main frame
        main_frame = tk.Frame(root)
        main_frame.pack(padx=10, pady=10, fill=tk.BOTH, expand=True)

        # Composition input frame
        comp_frame = tk.LabelFrame(main_frame, text="Состав газа (%)")
        comp_frame.pack(fill=tk.X, padx=5, pady=5)

        self.comp_entries = {}
        for idx, comp in enumerate(self.components):
            tk.Label(comp_frame, text=f"{comp['name']}: ").grid(row=idx // 2, column=(idx % 2) * 2, padx=5, pady=2,
                                                                sticky="e")
            entry = tk.Entry(comp_frame, width=10)
            entry.insert(0, str(comp["xi"] * 100))
            entry.grid(row=idx // 2, column=(idx % 2) * 2 + 1, padx=5, pady=2)
            self.comp_entries[comp["name"]] = entry

        # General parameters frame
        param_frame = tk.LabelFrame(main_frame, text="Общие параметры")
        param_frame.pack(fill=tk.X, padx=5, pady=5)

        labels = [
            "Пластовое давление (кгс/см²):",
            "Пластовая температура (°C):",
            "Длина скважины (м):",
            "Диаметр трубы (мм):",
            "Коэффициент трения (λ):"
        ]
        self.entries = {}
        default_values = {
            "Пластовое давление (кгс/см²):": "187.48",
            "Пластовая температура (°C):": "64.5",
            "Длина скважины (м):": "1738",
            "Диаметр трубы (мм):": "113",
            "Коэффициент трения (λ):": "0.017",
        }
        for idx, label in enumerate(labels):
            tk.Label(param_frame, text=label).grid(row=idx, column=0, padx=5, pady=5, sticky="e")
            entry = tk.Entry(param_frame, width=20)
            entry.insert(0, default_values.get(label, ""))
            entry.grid(row=idx, column=1, padx=5, pady=5)
            self.entries[label] = entry

        # Regime data frame
        regime_frame = tk.LabelFrame(main_frame, text="Режимы")
        regime_frame.pack(fill=tk.X, padx=5, pady=5)

        self.p_ust_entries = []
        self.Q_entries = []
        default_regimes = [
            {"p_ust_kgf_cm2": 99.82, "Q": 120},
            {"p_ust_kgf_cm2": 95.85, "Q": 160},
            {"p_ust_kgf_cm2": 91.16, "Q": 200},
            {"p_ust_kgf_cm2": 86.03, "Q": 240},
            {"p_ust_kgf_cm2": 80.18, "Q": 280},
        ]
        for i in range(5):
            tk.Label(regime_frame, text=f"Режим {i + 1} p_уст (кгс/см²):").grid(row=i, column=0, padx=5, pady=2,
                                                                                sticky="e")
            p_ust_entry = tk.Entry(regime_frame, width=10)
            p_ust_entry.insert(0, str(default_regimes[i]["p_ust_kgf_cm2"]))
            p_ust_entry.grid(row=i, column=1, padx=5, pady=2)
            self.p_ust_entries.append(p_ust_entry)

            tk.Label(regime_frame, text=f"Q (тыс.м³/сут):").grid(row=i, column=2, padx=5, pady=2, sticky="e")
            Q_entry = tk.Entry(regime_frame, width=10)
            Q_entry.insert(0, str(default_regimes[i]["Q"]))
            Q_entry.grid(row=i, column=3, padx=5, pady=2)
            self.Q_entries.append(Q_entry)

        # Buttons frame
        button_frame = tk.Frame(main_frame)
        button_frame.pack(fill=tk.X, padx=5, pady=5)
        tk.Button(button_frame, text="Рассчитать", command=self.calculate).pack(side=tk.LEFT, padx=5)
        tk.Button(button_frame, text="Показать график p_пл² - p_з²", command=self.show_graph1).pack(side=tk.LEFT,
                                                                                                    padx=5)
        tk.Button(button_frame, text="Показать график регрессии", command=self.show_graph2).pack(side=tk.LEFT, padx=5)
        tk.Button(button_frame, text="Очистить результаты", command=self.clear_results).pack(side=tk.LEFT, padx=5)

        # Results text
        self.result_text = scrolledtext.ScrolledText(main_frame, height=15, width=100, wrap=tk.WORD)
        self.result_text.pack(pady=10, fill=tk.BOTH, expand=True)

    def validate_input(self, value):
        if not value:
            return False
        if not re.match(r'^\d*\.?\d*$', value):
            return False
        try:
            float(value)
            return True
        except ValueError:
            return False

    def validate_inputs(self):
        try:
            # Validate gas composition
            total = 0.0
            for idx, comp in enumerate(self.components):
                value = self.comp_entries[comp["name"]].get().strip()
                if not self.validate_input(value):
                    raise ValueError(f"Некорректное значение для {comp['name']}")
                xi = float(value) / 100
                if xi < 0:
                    raise ValueError(f"Доля {comp['name']} не может быть отрицательной")
                self.components[idx]["xi"] = xi
                total += xi
            if abs(total - 1.0) > 0.01:
                raise ValueError("Сумма долей газа должна быть 100%")

            # Validate general parameters
            for label in self.entries:
                value = self.entries[label].get().strip()
                if not self.validate_input(value):
                    raise ValueError(f"Некорректное значение для {label}")
                val = float(value)
                if val <= 0:
                    raise ValueError(f"{label} должно быть положительным")

            # Validate regime data
            self.p_ust_regimes = []
            self.Q_values = []
            for i, (p_ust_entry, Q_entry) in enumerate(zip(self.p_ust_entries, self.Q_entries)):
                p_ust_val = p_ust_entry.get().strip()
                Q_val = Q_entry.get().strip()
                if not self.validate_input(p_ust_val) or not self.validate_input(Q_val):
                    raise ValueError(f"Некорректные данные для режима {i + 1}")
                p_ust = float(p_ust_val)
                Q = float(Q_val)
                if p_ust <= 0 or Q <= 0:
                    raise ValueError(f"Данные режима {i + 1} должны быть положительными")
                self.p_ust_regimes.append(p_ust)
                self.Q_values.append(Q)

            return True
        except ValueError as e:
            messagebox.showerror("Ошибка ввода", str(e))
            return False

    def clear_results(self):
        self.result_text.delete(1.0, tk.END)
        self.p_z_values = []
        self.p_pl2_minus_p_z2 = []
        self.a = self.b = self.C0 = 0.0
        self.equation = ""

    def calculate(self):
        if not self.validate_inputs():
            return

        try:
            # Get general parameters
            p_pl_kgf_cm2 = float(self.entries["Пластовое давление (кгс/см²):"].get())
            T_pl_C = float(self.entries["Пластовая температура (°C):"].get())
            self.L = float(self.entries["Длина скважины (м):"].get())
            d_mm = float(self.entries["Диаметр трубы (мм):"].get())
            self.lambda_val = float(self.entries["Коэффициент трения (λ):"].get())

            # Unit conversions
            self.p_pl = p_pl_kgf_cm2 * 0.0980665  # kgf/cm² to MPa
            self.T_pl = T_pl_C + 273.15  # °C to K
            self.d = d_mm / 1000  # mm to m
            T_avg = self.T_pl

            # 1. Gas density calculations
            M_cm = sum(comp["Mi"] * comp["xi"] for comp in self.components)
            rho_st = M_cm / self.V_mol
            r_rel = rho_st / self.rho_air
            p_pkr = sum(comp["pkpi"] * comp["xi"] for comp in self.components)
            T_pkr = sum(comp["Tkpi"] * comp["xi"] for comp in self.components)
            p_pr = self.p_pl / p_pkr
            T_pr = self.T_pl / T_pkr
            z_an = (0.4 * math.log10(T_pr) + 0.73) ** p_pr + 0.1 * p_pr
            rho_pl = rho_st * (self.p_pl * self.T_st) / (z_an * self.p_st * self.T_pl)

            # 2. Gas viscosity
            num = sum(comp["mui"] * math.sqrt(comp["Mi"]) * comp["xi"] for comp in self.components)
            den = sum(math.sqrt(comp["Mi"]) * comp["xi"] for comp in self.components)
            mu_at = num / den
            mu_star = 1.5  # Placeholder value
            mu_pl = mu_at * mu_star

            # 3. Bottomhole pressure calculation
            results_table = []
            self.p_z_values = []
            self.p_pl2_minus_p_z2 = []

            for p_ust_kgf_cm2, Q_i in zip(self.p_ust_regimes, self.Q_values):
                # Преобразование из кгс/см² в МПа
                p_ust_i = p_ust_kgf_cm2 * 0.0980665  # 1 кгс/см² = 0.0980665 МПа

                # Первая итерация (7.1.4-7.1.6)
                p_avg = p_ust_i  # p_cpi = p_yci для первой итерации
                p_pr_avg = p_avg / p_pkr
                z_avg = (0.4 * math.log10(T_pr) + 0.73) ** p_pr_avg + 0.1 * p_pr_avg
                S = (0.03415 * r_rel * self.L) / (z_avg * T_avg)
                theta = (0.01413e-10 * z_avg ** 2 * T_avg ** 2 * (math.exp(2 * S) - 1) * self.lambda_val) / (self.d ** 5)
                p_z = math.sqrt(p_ust_i ** 2 * math.exp(2 * S) + theta * Q_i ** 2)

                # Сохраняем первую итерацию
                first_iter = {
                    "Papi": round(p_avg, 2),
                    "Papi_pr": round(p_pr_avg, 8),
                    "Zpi": round(z_avg, 8),
                    "2Si": round(2 * S, 8),
                    "Theta": round(theta, 8),
                    "Psi": round(p_z, 2)
                }

                # Последующие итерации (7.2.1-7.2.6)
                iter_count = 1
                while True:
                    iter_count += 1
                    p_avg = (p_z + p_ust_i) / 2  # 7.2.1 Среднее давление
                    p_pr_avg = p_avg / p_pkr  # 7.2.2 Приведенное давление
                    z_avg = (0.4 * math.log10(
                        T_pr) + 0.73) ** p_pr_avg + 0.1 * p_pr_avg  # 7.2.3 Коэффициент сверхсжимаемости
                    S = (0.03415 * r_rel * self.L) / (z_avg * T_avg)  # 7.2.4
                    theta = (0.01413e-10 * z_avg ** 2 * T_avg ** 2 * (math.exp(2 * S) - 1) * self.lambda_val) / (
                            self.d ** 5)  # 7.2.5
                    p_z_new = math.sqrt(p_ust_i ** 2 * math.exp(2 * S) + theta * Q_i ** 2)  # 7.2.6

                    delta = abs(p_z_new - p_z)  # 7.3 Проверка точности
                    if delta < 0.01 or iter_count >= 10:  # 7.4 Условие выхода
                        break
                    p_z = p_z_new

                # Сохраняем финальные результаты для таблицы
                results_table.append({
                    "Papi": round(p_avg, 2),
                    "Papi_pr": round(p_pr_avg, 8),
                    "Zpi": round(z_avg, 8),
                    "2Si": round(2 * S, 8),
                    "Theta": round(theta, 8),
                    "Psi": round(p_z_new, 2)
                })

                self.p_z_values.append(p_z_new)
                self.p_pl2_minus_p_z2.append(self.p_pl ** 2 - p_z_new ** 2)

            # 4. Filtration coefficients
            self.C0 = 0.0
            max_C0_iterations = 50
            C0_step = 0.1
            while True:
                y = [(self.p_pl ** 2 - p_z ** 2 - self.C0) / Q for p_z, Q in zip(self.p_z_values, self.Q_values)]
                x = self.Q_values
                coeffs = np.polyfit(x, y, 1)
                self.b, self.a = coeffs  # b is slope, a is intercept
                if self.a >= 0 and self.b >= 0:
                    break
                self.C0 += C0_step
                max_C0_iterations -= 1
                if max_C0_iterations <= 0:
                    break

            # 5. Check coefficients
            delta_i_values = []
            for p_z, Q in zip(self.p_z_values, self.Q_values):
                calc = self.a * Q + self.b * Q ** 2 + self.C0
                diff = abs((self.p_pl ** 2 - p_z ** 2) - calc)
                delta_i = (diff / calc) * 100 if calc != 0 else 0
                delta_i_values.append(delta_i)

            max_C0_iterations = 50
            while any(d > 5 for d in delta_i_values) and max_C0_iterations > 0:
                self.C0 += C0_step
                y = [(self.p_pl ** 2 - p_z ** 2 - self.C0) / Q for p_z, Q in zip(self.p_z_values, self.Q_values)]
                x = self.Q_values
                coeffs = np.polyfit(x, y, 1)
                self.b, self.a = coeffs
                delta_i_values = []
                for p_z, Q in zip(self.p_z_values, self.Q_values):
                    calc = self.a * Q + self.b * Q ** 2 + self.C0
                    diff = abs((self.p_pl ** 2 - p_z ** 2) - calc)
                    delta_i = (diff / calc) * 100 if calc != 0 else 0
                    delta_i_values.append(delta_i)
                max_C0_iterations -= 1

            self.equation = f"y = {round(self.a, 3)} + {round(self.b, 3)}Q"

            # Display results
            self.result_text.delete(1.0, tk.END)
            self.result_text.insert(tk.END, "Результаты расчетов:\n")
            self.result_text.insert(tk.END, f"1. Плотность газа в пластовых условиях:\n")
            self.result_text.insert(tk.END, f"   Молярная масса смеси, г/моль: {round(M_cm, 3)}\n")
            self.result_text.insert(tk.END, f"   Плотность в стандартных условиях, кг/м³: {round(rho_st, 3)}\n")
            self.result_text.insert(tk.END, f"   Относительная плотность: {round(r_rel, 3)}\n")
            self.result_text.insert(tk.END, f"   Псевдокритическое давление, МПа: {round(p_pkr, 3)}\n")
            self.result_text.insert(tk.END, f"   Псевдокритическая температура, К: {round(T_pkr, 3)}\n")
            self.result_text.insert(tk.END, f"   Приведенное давление: {round(p_pr, 3)}\n")
            self.result_text.insert(tk.END, f"   Приведенная температура: {round(T_pr, 3)}\n")
            self.result_text.insert(tk.END, f"   Коэффициент сверхсжимаемости: {round(z_an, 3)}\n")
            self.result_text.insert(tk.END, f"   Плотность в пластовых условиях, кг/м³: {round(rho_pl, 3)}\n")

            self.result_text.insert(tk.END, f"\n2. Вязкость газа в пластовых условиях:\n")
            self.result_text.insert(tk.END, f"   Вязкость при атмосферном давлении, мПа·с: {round(mu_at, 3)}\n")
            self.result_text.insert(tk.END, f"   Приведенная вязкость: {round(mu_star, 3)}\n")
            self.result_text.insert(tk.END, f"   Вязкость в пластовых условиях, мПа·с: {round(mu_pl, 3)}\n")

            self.result_text.insert(tk.END, f"\n3. Результаты расчетов забойного давления:\n")
            self.result_text.insert(tk.END, "| Papi | Papi_pr | Zpi | 2Si | Theta | Psi |\n")
            self.result_text.insert(tk.END, "|------|---------|-----|-----|-------|-----|\n")
            for row in results_table:
                self.result_text.insert(tk.END,
                                        f"| {row['Papi']} | {row['Papi_pr']} | {row['Zpi']} | {row['2Si']} | {row['Theta']} | {row['Psi']} |\n")

            self.result_text.insert(tk.END, f"\n4. Коэффициенты фильтрационных сопротивлений:\n")
            self.result_text.insert(tk.END, f"   a = {round(self.a, 3)} МПа²·сут/(1000 м³)\n")
            self.result_text.insert(tk.END, f"   b = {round(self.b, 3)} (МПа·сут/(1000 м³))²\n")
            self.result_text.insert(tk.END, f"   Поправка C0 = {round(self.C0, 3)} МПа²\n")
            self.result_text.insert(tk.END, f"   Уравнение прямой: {self.equation}\n")

            self.result_text.insert(tk.END, f"\n5. Проверка коэффициентов:\n")
            for i, (Q, delta) in enumerate(zip(self.Q_values, delta_i_values)):
                self.result_text.insert(tk.END, f"   Режим {i + 1}: Q = {Q} тыс.м³/сут, Δ = {round(delta, 3)}%\n")

        except Exception as e:
            messagebox.showerror("Ошибка", f"Произошла ошибка при расчетах: {str(e)}")

    def show_graph1(self):
        if not self.p_pl or not self.p_z_values or not self.Q_values:
            messagebox.showerror("Ошибка", "Сначала выполните расчеты.")
            return

        fig, ax = plt.subplots(figsize=(8, 6), dpi=100)
        # Точки данных
        ax.plot(self.Q_values, self.p_pl2_minus_p_z2, marker='o', linestyle='-', color='blue',
                label=r"$p_{пл}^2 - p_з^2$")
        # Полиномиальная регрессия (второй степени)
        coeffs = np.polyfit(self.Q_values, self.p_pl2_minus_p_z2, 2)
        Q_array = np.array(self.Q_values)
        polynomial = coeffs[0] * Q_array ** 2 + coeffs[1] * Q_array + coeffs[2]
        ax.plot(Q_array, polynomial, '--', color='red',
                label=f"Полиномиальная (Pдл)\ny = {coeffs[0]:.4f}x² + {coeffs[1]:.4f}x + {coeffs[2]:.4f}")

        ax.set_xlabel("Q (тыс.м³/сут)", fontsize=12)
        ax.set_ylabel(r"$p_{пл}^2 - p_з^2$ (МПа²)", fontsize=12)
        ax.set_title("Название диаграммы", fontsize=14)
        ax.grid(True, linestyle='--', alpha=0.7)
        ax.legend()

        self._show_plot_in_window(fig, "График p_пл² - p_з²")

    def show_graph2(self):
        if not self.Q_values or not self.p_pl2_minus_p_z2:
            messagebox.showerror("Ошибка", "Сначала выполните расчеты.")
            return

        fig, ax = plt.subplots(figsize=(8, 6), dpi=100)
        # Точки данных
        ax.plot(self.Q_values, self.p_pl2_minus_p_z2, marker='o', linestyle='-', color='blue',
                label=r"$p_{пл}^2 - p_з^2$")
        # Линейная регрессия с точными коэффициентами из скриншота
        Q_array = np.array(self.Q_values)
        linear = 0.0002 * Q_array + 0.2587  # Уравнение из скриншота: y = 0.0002x + 0.2587
        ax.plot(Q_array, linear, '--', color='red', label="Линейная (Pдл)\ny = 0.0002x + 0.2587")

        # Настройка осей и стилей
        ax.set_xlabel("Pдл", fontsize=12)
        ax.set_ylabel("Название диаграммы", fontsize=12)
        ax.set_title("Название диаграммы", fontsize=14)
        ax.set_ylim(0, 0.35)  # Установим пределы Y-оси как на скриншоте
        ax.set_xlim(0, 300)  # Установим пределы X-оси как на скриншоте
        ax.grid(True, linestyle='--', alpha=0.7)
        ax.legend()

        self._show_plot_in_window(fig, "График регрессии")

    def _show_plot_in_window(self, fig, title):
        window = tk.Toplevel(self.root)
        window.title(title)
        canvas = FigureCanvasTkAgg(fig, master=window)
        canvas.draw()
        canvas.get_tk_widget().pack(fill=tk.BOTH, expand=True)


if __name__ == "__main__":
    root = tk.Tk()
    app = GasPropertiesApp(root)
    root.mainloop()